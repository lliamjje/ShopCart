import { test, type TestContext } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import request, { type Response } from 'supertest';
import type { Express } from 'express';
import { loadIntegrationConfig, applyIntegrationConfig } from './config.js';

type Row = Record<string, unknown>;
const prefix = '/api/v1';
function object(value: unknown): Row {
  assert.ok(value !== null && typeof value === 'object' && !Array.isArray(value), 'Se esperaba un objeto del contrato HTTP.');
  return value as Row;
}
function rows(value: unknown): Row[] {
  assert.ok(Array.isArray(value), 'Se esperaba una colección del contrato HTTP.');
  return value.map(object);
}
function id(value: unknown): string {
  assert.equal(typeof value, 'string', 'bigint debe viajar como texto.');
  assert.match(value as string, /^[1-9]\d*$/);
  return value as string;
}
function intId(value: unknown): number {
  assert.equal(typeof value, 'number');
  assert.ok(Number.isInteger(value) && Number(value) > 0);
  return value as number;
}
// Aserciones numéricas exactas, sin convertir dinero a coma flotante.
function money(value: unknown): bigint {
  assert.equal(typeof value, 'string', 'Importes HTTP deben ser strings.');
  assert.match(value as string, /^-?\d+\.\d{4}$/);
  return BigInt((value as string).replace('.', ''));
}
function state(value: unknown, expected: string): void { assert.equal(object(value).Estado, expected); }
function data(response: Response, status = 200): Row {
  // No imprimir body: podría contener JWT, cookies, perfiles o información SQL.
  const code: unknown = response.body?.error?.code;
  const safeCode = typeof code === 'string' && /^[A-Z0-9_]+$/.test(code) ? code : 'SIN_CODIGO';
  assert.equal(response.status, status, `HTTP esperado ${status}, recibido ${response.status}; código público ${safeCode}.`);
  assert.equal(response.body.success, true);
  return object(response.body.data);
}
function rejected(response: Response, status: number, code?: string): void {
  const received: unknown = response.body?.error?.code;
  const safeCode = typeof received === 'string' && /^[A-Z0-9_]+$/.test(received) ? received : 'SIN_CODIGO';
  assert.equal(response.status, status, `Error HTTP esperado ${status}, recibido ${response.status}; código público ${safeCode}.`);
  assert.equal(response.body.success, false);
  if (code) assert.equal(response.body.error?.code, code);
}

class Client {
  readonly agent;
  csrf = '';
  token = '';
  userId = '';
  constructor(app: Express) { this.agent = request.agent(app); }
  async init(): Promise<void> {
    const response = await this.agent.get(`${prefix}/auth/csrf`);
    const payload = data(response);
    assert.equal(typeof payload.csrfToken, 'string');
    this.csrf = payload.csrfToken as string;
    const cookies = response.headers['set-cookie'] as unknown as string[];
    assert.ok(cookies.some(c => c.startsWith('sc_csrf=') && /SameSite=Strict/i.test(c)));
  }
  async call(method: 'get' | 'post' | 'patch' | 'delete', path: string,
      body?: Row, key?: string): Promise<Response> {
    let pending = this.agent[method](`${prefix}${path}`).set('X-CSRF-Token', this.csrf)
      .set('Origin', 'http://127.0.0.1:5173').timeout({ response: 20000, deadline: 30000 });
    if (this.token) pending = pending.set('Authorization', `Bearer ${this.token}`);
    if (key) pending = pending.set('Idempotency-Key', key);
    if (body) pending = pending.send(body);
    try { return await pending; }
    catch { throw new Error(`Transporte HTTP falló: ${method.toUpperCase()} ${path.split('?')[0]}; sin detalles sensibles.`); }
  }
  async login(email: string, password: string, role: string): Promise<Response> {
    const response = await this.call('post', '/auth/login', { email, password });
    const payload = data(response);
    assert.equal(object(payload.profile).Rol, role);
    this.userId = id(object(payload.profile).IdUsuario);
    assert.equal(typeof payload.accessToken, 'string');
    this.token = payload.accessToken as string;
    const claims = object(JSON.parse(Buffer.from(this.token.split('.')[1]!, 'base64url').toString('utf8')));
    assert.equal(claims.sub, this.userId);
    assert.equal(claims.iss, 'shopcart');
    assert.equal(claims.aud, 'shopcart-api');
    assert.ok(Number(claims.exp) > Number(claims.iat));
    const cookies = response.headers['set-cookie'] as unknown as string[];
    assert.ok(cookies.some(c => c.startsWith('sc_refresh=') && /HttpOnly/i.test(c) && /SameSite=Strict/i.test(c)));
    return response;
  }
}

test('ShopCart — integración HTTP con SQL Server real (sin mocks)', { timeout: 240000 }, async t => {
  // Si falta aislamiento, falla ANTES de importar src o abrir un socket SQL.
  const config = loadIntegrationConfig();
  if (config.selected.has('commerce') || config.selected.has('reports')) {
    assert.ok(config.values.INTEGRATION_ADMIN_EMAIL && config.values.INTEGRATION_ADMIN_PASSWORD,
      'BLOQUEO administrativo: commerce/reports requieren un Administrador legítimo aprovisionado en la instancia aislada; 013/021 no inicializan el primero.');
  }
  applyIntegrationConfig(config);
  const { createApp } = await import('../../src/app.js');
  const { closePool } = await import('../../src/config/database.js');
  const app = createApp(); // Importa el adaptador real, sin modificar ConnectionPool ni repositorios.
  const run = randomUUID().replaceAll('-', '');
  const password = `IT-${randomBytes(24).toString('base64url')}aA1!`;
  const from = new Date(Date.now() - 60000).toISOString();
  const to = new Date(Date.now() + 86400000).toISOString();
  const interval = `from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`;
  const sessions: Client[] = [];
  const anonymous = new Client(app);
  let usersPromise: Promise<[Client, Client]> | undefined;
  let adminPromise: Promise<Client> | undefined;
  let fixturePromise: Promise<Fixture> | undefined;
  let counter = 0;
  const pendingCheckouts: { client: Client; checkoutId: string }[] = [];
  const createdUsers: Client[] = [];
  let cleanupFixture: Partial<Fixture> = {};
  const key = (label: string) => `${run}_${label}_${++counter}`;
  const scenario = (context: TestContext, name: string, fn: () => Promise<void>) =>
    context.test(name, { timeout: 60000 }, fn);

  async function registered(label: string): Promise<Client> {
    const client = new Client(app);
    await client.init();
    const email = `it-${run}-${label}@example.invalid`;
    client.userId = id(data(await client.call('post', '/auth/register', {
      firstName: 'Integración', lastName: label, email, password,
    }), 201).IdUsuario);
    createdUsers.push(client);
    await client.login(email, password, 'Cliente');
    sessions.push(client);
    return client;
  }
  function users(): Promise<[Client, Client]> {
    return usersPromise ??= (async () => [await registered('cliente'), await registered('otro')] as [Client, Client])();
  }
  function admin(): Promise<Client> {
    return adminPromise ??= (async () => {
      const client = new Client(app);
      await client.init();
      await client.login(config.values.INTEGRATION_ADMIN_EMAIL!, config.values.INTEGRATION_ADMIN_PASSWORD!, 'Administrador');
      sessions.push(client);
      return client;
    })();
  }
  interface Fixture { categoryId: number; productId: string; variantId: string; couponId: string; couponCode: string; shippingId: number }
  function fixture(): Promise<Fixture> {
    return fixturePromise ??= (async () => {
      const operator = await admin();
      const categoryId = intId(object(data(await operator.call('post', '/catalog/categories', {
        name: `IT ${run}`, description: 'Fixture aislado de integración', active: true,
      }), 201).category).IdCategoria);
      cleanupFixture.categoryId = categoryId;
      const productId = id(object(data(await operator.call('post', '/catalog/products', {
        categoryId, name: `IT ${run}`, description: 'Fixture aislado', active: false,
      }), 201).product).IdProducto);
      cleanupFixture.productId = productId;
      const variantId = id(object(data(await operator.call('post', '/catalog/variants', {
        productId, sku: `IT-${run}`, price: '112.0000', active: true,
      }), 201).variant).IdVariante);
      cleanupFixture.variantId = variantId;
      data(await operator.call('post', '/inventory/movements', {
        variantId, type: 'ENTRADA', quantity: 20, reason: `IT ${run}`,
        operationId: BigInt(`0x${randomBytes(7).toString('hex')}`).toString(),
      }), 201);
      data(await operator.call('patch', `/catalog/products/${productId}`, {
        categoryId, name: `IT ${run}`, description: 'Fixture aislado', active: true,
      }));
      const couponCode = `IT-${run.toUpperCase()}`;
      const couponId = id(object(data(await operator.call('post', '/coupons', {
        code: couponCode, type: 'PORCENTAJE', value: '10.0000', minimum: '1.0000',
        startsAt: from, endsAt: to, categoryId, globalLimit: 20, userLimit: 10,
        active: true, description: `IT ${run}`,
      }), 201).coupon).IdCupon);
      cleanupFixture.couponId = couponId;
      const shipping = rows(data(await anonymous.call('get', '/shipping-methods')).shippingMethods)
        .find(row => row.Codigo === 'RETIRO_TIENDA');
      assert.ok(shipping, 'Falta RETIRO_TIENDA de la configuración 021.');
      assert.equal(money(shipping.Costo), 0n);
      return { categoryId, productId, variantId, couponId, couponCode, shippingId: intId(shipping.IdMetodoEnvio) };
    })();
  }
  async function inventory(): Promise<Row> {
    const f = await fixture();
    const result = rows(data(await (await admin()).call('get', `/inventory?variantId=${f.variantId}`)).inventory);
    assert.equal(result.length, 1);
    return result[0]!;
  }
  async function cart(client: Client): Promise<Row> { return data(await client.call('get', '/carts/current')); }
  async function checkout(client: Client, coupon = false): Promise<{ checkoutId: string; orderId: string; payload: Row; operationKey: string }> {
    const f = await fixture();
    await cart(client);
    data(await client.call('delete', '/carts/current/items'));
    data(await client.call('post', '/carts/current/items', { variantId: f.variantId, quantity: 2 }));
    const current = object((await cart(client)).cart);
    const payload = { cartId: id(current.IdCarrito), cartRevision: current.RevisionCarrito,
      shippingMethodId: f.shippingId, recipientName: 'Prueba aislada', phone: '55550000',
      department: 'Guatemala', city: 'Guatemala', address1: 'Dirección de prueba',
      ...(coupon ? { couponCode: f.couponCode } : {}) };
    const operationKey = key('checkout');
    const result = object(data(await client.call('post', '/checkouts', payload, operationKey), 201).checkout);
    const checkoutId = id(result.IdCheckout), orderId = id(result.IdPedido);
    pendingCheckouts.push({ client, checkoutId });
    return { checkoutId, orderId, payload, operationKey };
  }
  function resolved(checkoutId: string): void {
    const index = pendingCheckouts.findIndex(row => row.checkoutId === checkoutId);
    if (index >= 0) pendingCheckouts.splice(index, 1);
  }
  async function paid(client: Client): Promise<{ checkoutId: string; orderId: string }> {
    const c = await checkout(client, true);
    state(data(await client.call('post', '/orders/payments', { orderId: c.orderId, action: 'APROBAR' }, key('payment'))).payment, 'APROBADO');
    resolved(c.checkoutId);
    return c;
  }

  // El hook se registra antes de preparar datos y nunca borra datos históricos.
  t.after(async () => {
    const failures: string[] = [];
    for (const owned of pendingCheckouts) {
      try { data(await owned.client.call('post', `/checkouts/${owned.checkoutId}/cancel`, {})); }
      catch { failures.push('cancelar reserva propia pendiente'); }
    }
    if (adminPromise) {
      const operator = await adminPromise.catch(() => undefined);
      if (operator) {
        const f = cleanupFixture;
        const actions: [string, () => Promise<Response>][] = [];
        if (f.couponId) actions.push(['desactivar cupón propio', () => operator.call('patch', `/coupons/${f.couponId}/state`, { active: false })]);
        if (f.productId && f.categoryId) actions.push(['desactivar producto propio', () => operator.call('patch', `/catalog/products/${f.productId}`, {
          categoryId: f.categoryId, name: `IT ${run}`, description: 'Fixture aislado', active: false,
        })]);
        if (f.categoryId) actions.push(['desactivar categoría propia', () => operator.call('patch', `/catalog/categories/${f.categoryId}`, {
          name: `IT ${run}`, description: 'Fixture aislado de integración', active: false,
        })]);
        // Usuarios se conservan; solo se desactivan los registrados por esta ejecución.
        for (const client of createdUsers) actions.push(['desactivar usuario propio', () => operator.call('patch', `/users/${client.userId}/access`, { role: 'Cliente', active: false })]);
        // Revocar primero todas las sesiones abiertas por la suite, incluida la administrativa.
        for (const client of sessions.filter(client => client !== operator)) {
          try { data(await client.call('post', '/auth/logout', { all: false })); client.token = ''; }
          catch { failures.push('revocar sesión propia'); }
        }
        for (const [label, action] of actions) { try { data(await action()); } catch { failures.push(label); } }
      }
    }
    for (const client of sessions.filter(client => client.token)) {
      try { data(await client.call('post', '/auth/logout', { all: false })); } catch { failures.push('revocar sesión propia'); }
    }
    await closePool();
    assert.equal(failures.length, 0, `Limpieza incompleta: ${failures.join(', ')}. Conservar la instancia para revisar; no borrar datos automáticamente.`);
  });

  await anonymous.init();
  // Precondición compartida, incluso al seleccionar un solo módulo.
  const health = data(await anonymous.call('get', '/health?database=true'));
  assert.equal(health.http, 'up');
  assert.equal(health.database, 'connected', 'La API debe conectar a SQL Server real.');
  t.diagnostic(`Ejecución ${run}; grupos: ${[...config.selected].join(', ')}. No se imprimen credenciales.`);

  if (config.selected.has('smoke')) await t.test('smoke — disponibilidad y catálogo real', async context => {
    await scenario(context, 'HTTP y conexión SQL real', async () => {
      assert.equal(data(await anonymous.call('get', '/health?database=true')).database, 'connected');
    });
    await scenario(context, 'categorías y métodos iniciales 021', async () => {
      const categories = rows(data(await anonymous.call('get', '/catalog/categories')).categories);
      for (const name of ['Electrónica', 'Ropa', 'Hogar', 'Accesorios']) assert.ok(categories.some(c => c.Nombre === name));
      const shipping = rows(data(await anonymous.call('get', '/shipping-methods')).shippingMethods);
      for (const code of ['ESTANDAR', 'EXPRES', 'RETIRO_TIENDA']) assert.ok(shipping.some(s => s.Codigo === code));
      for (const row of shipping) assert.ok(money(row.Costo) >= 0n);
    });
    await scenario(context, 'paginación y validación del catálogo', async () => {
      assert.ok(rows(data(await anonymous.call('get', '/catalog/products?page=1&pageSize=2')).products).length <= 2);
      rejected(await anonymous.call('get', '/catalog/products?pageSize=101'), 400);
    });
  });

  if (config.selected.has('auth')) await t.test('auth — registro, cookies, JWT, CSRF y autorización', async context => {
    await scenario(context, 'CSRF faltante, incorrecto y origen ajeno', async () => {
      rejected(await request(app).post(`${prefix}/auth/login`).send({}), 403, 'CSRF_REJECTED');
      rejected(await anonymous.agent.post(`${prefix}/auth/login`).set('X-CSRF-Token', 'A'.repeat(43)).send({}), 403, 'CSRF_REJECTED');
      rejected(await anonymous.agent.post(`${prefix}/auth/login`).set('X-CSRF-Token', anonymous.csrf).set('Origin', 'https://other.invalid').send({}), 403, 'CSRF_REJECTED');
    });
    await scenario(context, 'registro e inicio real; JWT permite consultar perfil', async () => {
      const [client] = await users();
      assert.equal(object(data(await client.call('get', '/users/me')).profile).IdUsuario, client.userId);
      rejected(await client.call('post', '/auth/register', { firstName: 'Duplicado', lastName: 'IT',
        email: `it-${run}-cliente@example.invalid`, password }), 409, 'DUPLICATE_RESOURCE');
      rejected(await anonymous.call('post', '/auth/login', { email: `it-${run}-cliente@example.invalid`, password: `${password}wrong` }), 401, 'INVALID_CREDENTIALS');
    });
    await scenario(context, 'anónimo 401; Cliente no puede administrar ni elevar su rol', async () => {
      const [client] = await users();
      rejected(await anonymous.call('get', '/inventory'), 401);
      rejected(await client.call('get', '/inventory'), 403);
      rejected(await client.call('get', '/audit'), 403);
      rejected(await client.call('patch', `/users/${client.userId}/access`, { role: 'Administrador', active: true }), 403);
      rejected(await client.call('post', '/auth/register', { firstName: 'IT', lastName: 'IT', email: `it-${run}-invalid@example.invalid`, password, role: 'Administrador' }), 400);
      rejected(await anonymous.agent.get(`${prefix}/users/me`).set('Authorization', `Bearer ${client.token.slice(0, -8)}XXXXXXXX`), 401);
    });
    await scenario(context, 'propiedad: otro Cliente no puede leer carrito ni dirección ajenos', async () => {
      const [owner, other] = await users();
      const ownCart = object((await cart(owner)).cart);
      rejected(await other.call('get', `/carts/${id(ownCart.IdCarrito)}`), 403);
      const address = { recipientName: 'IT', phone: '55550000', department: 'Guatemala', city: 'Guatemala', address1: 'Prueba aislada', primary: true, active: true };
      const addressId = id(object(data(await owner.call('post', '/users/me/addresses', address), 201).address).IdDireccion);
      rejected(await other.call('patch', `/users/me/addresses/${addressId}`, address), 403);
    });
    await scenario(context, 'refresh rota cookie real; logout invalida JWT y refresh', async () => {
      const [client] = await users();
      const renewed = await client.call('post', '/auth/refresh', {});
      client.token = data(renewed).accessToken as string;
      assert.ok((renewed.headers['set-cookie'] as unknown as string[]).some(c => c.startsWith('sc_refresh=')));
      data(await client.call('get', '/users/me'));
      const previous = client.token;
      data(await client.call('post', '/auth/logout', { all: false }));
      client.token = '';
      rejected(await anonymous.agent.get(`${prefix}/users/me`).set('Authorization', `Bearer ${previous}`), 401);
      rejected(await client.call('post', '/auth/refresh', {}), 401);
      // Nueva sesión legítima para los siguientes módulos, nunca un JWT construido por la prueba.
      await client.login(`it-${run}-cliente@example.invalid`, password, 'Cliente');
    });
  });

  if (config.selected.has('commerce')) await t.test('commerce — inventario, compra y postventa', async context => {
    await scenario(context, 'fixture propio; existencia, disponibilidad, carrito y cupón', async () => {
      const f = await fixture();
      const [client] = await users();
      assert.equal(Number((await inventory()).CantidadFisica), 20);
      await cart(client);
      data(await client.call('post', '/carts/current/items', { variantId: f.variantId, quantity: 2 }));
      assert.equal(rows((await cart(client)).items).length, 1);
      data(await client.call('patch', `/carts/current/items/${f.variantId}`, { quantity: 3 }));
      const current = await cart(client);
      assert.equal(rows(current.items)[0]!.Cantidad, 3);
      const quote = object(data(await client.call('post', '/coupons/validate', { cartId: id(object(current.cart).IdCarrito), code: f.couponCode })).quote);
      assert.equal(money(quote.Subtotal), 3360000n);
      assert.equal(money(quote.Descuento), 336000n);
      rejected(await client.call('post', '/coupons/validate', { cartId: id(object(current.cart).IdCarrito), code: `NO-${run}` }), 404, 'SQL_62604');
      data(await client.call('delete', `/carts/current/items/${f.variantId}`));
      assert.equal(rows((await cart(client)).items).length, 0);
      data(await client.call('post', '/carts/current/items', { variantId: f.variantId, quantity: 1 }));
      rejected(await client.call('patch', `/carts/current/items/${f.variantId}`, { quantity: 21 }), 409);
      rejected(await client.call('patch', `/carts/current/items/${f.variantId}`, { quantity: 0 }), 400);
      data(await client.call('delete', `/carts/current/items/${f.variantId}`));
      assert.equal(rows((await cart(client)).items).length, 0);
    });
    await scenario(context, 'Operador legítimo consulta inventario y no administra catálogo', async () => {
      const operator = await registered('operador');
      const administrator = await admin();
      data(await administrator.call('patch', `/users/${operator.userId}/access`, { role: 'Operador', active: true }));
      operator.token = ''; // SQL revocó la sesión anterior al cambiar el rol.
      await operator.login(`it-${run}-operador@example.invalid`, password, 'Operador');
      rows(data(await operator.call('get', '/inventory')).inventory);
      rejected(await operator.call('post', '/catalog/categories', { name: `PROHIBIDO-${run}`, active: true }), 403);
    });
    await scenario(context, 'carrito invitado usa cookie HttpOnly y queda aislado de otro invitado', async () => {
      const f = await fixture();
      const guest = new Client(app), stranger = new Client(app);
      await guest.init(); await stranger.init();
      const response = await guest.call('get', '/carts/current');
      const current = object(data(response).cart);
      assert.ok((response.headers['set-cookie'] as unknown as string[]).some(c => c.startsWith('sc_guest=') && /HttpOnly/i.test(c)));
      data(await guest.call('post', '/carts/current/items', { variantId: f.variantId, quantity: 1 }));
      assert.equal(rows((await cart(guest)).items).length, 1);
      data(await guest.call('delete', '/carts/current/items'));
      await cart(stranger);
      rejected(await stranger.call('get', `/carts/${id(current.IdCarrito)}`), 403);
    });
    await scenario(context, 'concurrencia: dos invitados disputan una última unidad sin sobreventa', async () => {
      const f = await fixture(), administrator = await admin();
      const variantId = id(object(data(await administrator.call('post', '/catalog/variants', {
        productId: f.productId, sku: `IT-${run}-LAST`, price: '112.0000', size: 'CONCURRENCIA', active: true,
      }), 201).variant).IdVariante);
      data(await administrator.call('post', '/inventory/movements', {
        variantId, type: 'ENTRADA', quantity: 1, reason: `IT ${run} concurrencia`,
        operationId: BigInt(`0x${randomBytes(7).toString('hex')}`).toString(),
      }), 201);
      const guests = [new Client(app), new Client(app)];
      const attempts: { client: Client; payload: Row; key: string }[] = [];
      for (const guest of guests) {
        await guest.init(); await cart(guest);
        data(await guest.call('post', '/carts/current/items', { variantId, quantity: 1 }));
        const current = object((await cart(guest)).cart);
        attempts.push({ client: guest, key: key('last_unit'), payload: {
          cartId: id(current.IdCarrito), cartRevision: current.RevisionCarrito,
          shippingMethodId: f.shippingId, recipientName: 'IT', phone: '55550000',
          department: 'Guatemala', city: 'Guatemala', address1: 'Prueba aislada',
        } });
      }
      const responses = await Promise.all(attempts.map(a => a.client.call('post', '/checkouts', a.payload, a.key)));
      for (let index = 0; index < responses.length; index++) {
        const response = responses[index]!;
        if (response.status !== 201) continue;
        const checkoutId = id(object(data(response, 201).checkout).IdCheckout);
        pendingCheckouts.push({ client: attempts[index]!.client, checkoutId });
      }
      const reserved = rows(data(await administrator.call('get', `/inventory?variantId=${variantId}`)).inventory)[0]!;
      assert.equal(Number(reserved.CantidadFisica), 1);
      assert.equal(Number(reserved.CantidadReservada), 1);
      assert.equal(Number(reserved.Disponible), 0);
      // Liberar primero los checkouts propios, incluso si después falla el contrato de error.
      for (const owned of [...pendingCheckouts]) {
        if (!attempts.some(a => a.client === owned.client)) continue;
        data(await owned.client.call('post', `/checkouts/${owned.checkoutId}/cancel`, {}));
        resolved(owned.checkoutId);
      }
      assert.deepEqual(responses.map(r => r.status).sort(), [201, 409], 'Solo un checkout debe reservar; el otro debe informar conflicto de disponibilidad.');
    });
    await scenario(context, 'checkout idempotente reserva stock y cupón; cancelación libera', async () => {
      const [client, other] = await users();
      const before = Number((await inventory()).Disponible);
      const c = await checkout(client, true);
      const repeat = object(data(await client.call('post', '/checkouts', c.payload, c.operationKey), 201).checkout);
      assert.equal(repeat.IdCheckout, c.checkoutId);
      assert.equal(repeat.IdPedido, c.orderId);
      const detail = data(await client.call('get', `/checkouts/${c.checkoutId}`));
      state(detail.checkout, 'RESERVADO');
      assert.equal(rows(detail.inventoryReservations).filter(r => r.Estado === 'ACTIVA').length, 1);
      assert.equal(rows(detail.couponReservations).filter(r => r.Estado === 'ACTIVA').length, 1);
      assert.equal(Number((await inventory()).Disponible), before - 2);
      data(await client.call('post', `/checkouts/${c.checkoutId}/cancel`, {}));
      resolved(c.checkoutId);
      state(data(await client.call('get', `/checkouts/${c.checkoutId}`)).checkout, 'CANCELADO');
      assert.equal(Number((await inventory()).Disponible), before);
      rejected(await other.call('get', `/checkouts/${c.checkoutId}`), 403);
      rejected(await other.call('get', `/orders/${c.orderId}`), 403);
      rejected(await client.call('post', '/checkouts', { ...c.payload, address1: 'Contenido distinto' }, c.operationKey), 409);
    });
    await scenario(context, 'pago rechazado y aprobado; reintentos no duplican stock ni usos', async () => {
      const [client] = await users();
      const f = await fixture();
      const before = Number((await inventory()).CantidadFisica);
      const c = await checkout(client, true);
      const declinedKey = key('decline');
      for (let i = 0; i < 2; i++) state(data(await client.call('post', '/orders/payments', { orderId: c.orderId, action: 'RECHAZAR' }, declinedKey)).payment, 'RECHAZADO');
      assert.equal(Number((await inventory()).CantidadFisica), before);
      const paymentKey = key('approve');
      const payment = object(data(await client.call('post', '/orders/payments', { orderId: c.orderId, action: 'APROBAR' }, paymentKey)).payment);
      resolved(c.checkoutId);
      state(payment, 'APROBADO');
      assert.equal(money(payment.Monto), 2016000n);
      const repeated = object(data(await client.call('post', '/orders/payments', { orderId: c.orderId, action: 'APROBAR' }, paymentKey)).payment);
      assert.equal(repeated.IdPago, payment.IdPago);
      assert.equal(Number((await inventory()).CantidadFisica), before - 2);
      const order = data(await client.call('get', `/orders/${c.orderId}`));
      state(order.order, 'PAGADO');
      assert.equal(rows(order.payments).filter(p => p.Estado === 'APROBADO').length, 1);
      const uses = rows(data(await (await admin()).call('get', `/coupons/${f.couponId}/uses`)).uses);
      assert.equal(uses.filter(u => u.IdPedido === c.orderId).length, 1);
      const cancelKey = key('cancel');
      for (let i = 0; i < 2; i++) {
        const cancelled = data(await client.call('post', `/orders/${c.orderId}/cancel`, {}, cancelKey));
        state(cancelled.order, 'CANCELADO');
        assert.equal(rows(cancelled.refunds).length, 1);
        assert.equal(money(rows(cancelled.refunds)[0]!.Monto), 2016000n);
      }
      assert.equal(Number((await inventory()).CantidadFisica), before);
    });
    await scenario(context, 'pedido entregado; devolución parcial, capacidad y reembolso idempotente', async () => {
      const [client, other] = await users();
      const operator = await admin();
      const c = await paid(client);
      const order = data(await client.call('get', `/orders/${c.orderId}`));
      const lineId = id(rows(order.items)[0]!.IdDetallePedido);
      rejected(await client.call('patch', `/orders/${c.orderId}/state`, { state: 'ENVIADO' }), 403);
      for (const next of ['EN_PREPARACION', 'ENVIADO', 'ENTREGADO']) data(await operator.call('patch', `/orders/${c.orderId}/state`, { state: next, note: `IT ${run}` }));
      const delivered = data(await client.call('get', `/orders/${c.orderId}`));
      state(delivered.order, 'ENTREGADO');
      assert.ok(rows(delivered.history).length >= 5);
      const payload = { orderId: c.orderId, items: [{ orderItemId: lineId, quantity: 1 }], reason: `IT ${run}` };
      const operation = randomUUID();
      const returnId = id(object(data(await client.call('post', '/returns', payload, operation), 201).return).IdDevolucion);
      assert.equal(object(data(await client.call('post', '/returns', payload, operation), 201).return).IdDevolucion, returnId);
      for (const next of ['APROBADA', 'RECIBIDA']) data(await operator.call('patch', `/returns/${returnId}/state`, { state: next, note: `IT ${run}` }));
      const before = Number((await inventory()).CantidadFisica);
      const refundKey = key('refund');
      for (let i = 0; i < 2; i++) {
        const completed = data(await operator.call('post', `/returns/${returnId}/complete`, {}, refundKey));
        assert.equal(money(object(completed.return).MontoReembolsable), 1008000n);
        assert.equal(rows(completed.refunds).length, 1);
      }
      assert.equal(Number((await inventory()).CantidadFisica), before + 1);
      for (let i = 0; i < 2; i++) state(data(await operator.call('post', `/returns/${returnId}/refunds`, { action: 'APROBAR' }, refundKey)).refund, 'APROBADO');
      const result = data(await client.call('get', `/orders/${c.orderId}/returns`));
      state(rows(result.returns)[0], 'COMPLETADA');
      assert.equal(rows(result.refunds).filter(r => r.Estado === 'APROBADO').length, 1);
      assert.equal(money(rows(result.refunds)[0]!.Monto), 1008000n);
      rejected(await client.call('post', `/orders/${c.orderId}/cancel`, {}, key('late_cancel')), 409);
      rejected(await other.call('post', '/returns', payload, randomUUID()), 403);
      rejected(await client.call('post', '/returns', { ...payload, items: [{ orderItemId: lineId, quantity: 2 }] }, randomUUID()), 409);
    });
  });

  if (config.selected.has('reports')) await t.test('reports — reportes y auditoría reales', async context => {
    await scenario(context, 'venta propia entregada incrementa unidades e importe de su categoría histórica', async () => {
      const operator = await admin(), f = await fixture();
      async function categorySale(): Promise<{ units: bigint; amount: bigint }> {
        // No depender de que la categoría nueva aparezca en la primera página.
        for (let page = 1; page <= 1000; page++) {
          const batch = rows(data(await operator.call('get', `/reports/sales?${interval}&dimension=CATEGORIA&pageSize=100&page=${page}`)).sales);
          const own = batch.find(row => row.Clave === String(f.categoryId));
          if (own) return { units: BigInt(String(own.UnidadesNetas)), amount: money(own.VentasNetasProductos) };
          if (batch.length < 100) return { units: 0n, amount: 0n };
        }
        throw new Error('La paginación del entorno aislado excede el límite de revisión de la prueba.');
      }
      const before = await categorySale();
      const [client] = await users();
      const c = await paid(client);
      for (const next of ['EN_PREPARACION', 'ENVIADO', 'ENTREGADO'])
        data(await operator.call('patch', `/orders/${c.orderId}/state`, { state: next, note: `IT ${run}` }));
      const after = await categorySale();
      assert.equal(after.units - before.units, 2n);
      assert.equal(after.amount - before.amount, 2016000n);
    });
    await scenario(context, 'ventas, finanzas y operación devuelven sus contratos', async () => {
      const operator = await admin();
      await fixture();
      for (const dimension of ['DIA', 'SEMANA', 'MES', 'PRODUCTO', 'CATEGORIA', 'TOP']) {
        const report = data(await operator.call('get', `/reports/sales?${interval}&dimension=${dimension}`));
        rows(report.sales); object(report.shipping);
      }
      const finance = data(await operator.call('get', `/reports/finance?${interval}`));
      object(finance.cashFlow); object(finance.averageTicket); rows(finance.ordersByState); rows(finance.returnsByState);
      for (const module of ['INVENTARIO', 'MOVIMIENTOS', 'RESERVAS', 'DEVOLUCIONES', 'REEMBOLSOS', 'CUPONES']) rows(data(await operator.call('get', `/reports/operations?${interval}&module=${module}`)).rows);
      rejected(await operator.call('get', `/reports/sales?from=${encodeURIComponent(to)}&to=${encodeURIComponent(from)}`), 400, 'INVALID_DATE_RANGE');
    });
    await scenario(context, 'auditoría contiene evento de creación del fixture propio', async () => {
      const operator = await admin();
      const f = await fixture();
      const events = rows(data(await operator.call('get', `/audit?${interval}&entity=Categorias&userId=${operator.userId}&pageSize=100`)).events);
      const own = events.find(e => String(e.IdEntidad) === String(f.categoryId));
      assert.ok(own, 'Debe existir auditoría para la categoría creada por esta ejecución.');
      assert.equal(own.IdUsuarioActor, operator.userId);
      assert.equal(typeof own.DatosNuevos, 'string');
      const audit = object(JSON.parse(own.DatosNuevos as string));
      assert.equal(audit.Nombre, `IT ${run}`);
      assert.ok(!/password|HashContrasena|TokenInvitadoHash/.test(own.DatosNuevos as string));
    });
  });
});

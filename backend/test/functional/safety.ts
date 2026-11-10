export type Kind = 'user'|'category'|'product'|'variant'|'cart'|'coupon'|'checkout'|'order'|'return'|'address'|'line'|'image';
export class Owned {
  private readonly resources = new Map<Kind, Set<string>>();
  constructor(readonly batch?:string) {}
  add(kind: Kind, value: string | number): string {
    const key = String(value);
    if (!/^[1-9]\d*$/.test(key)) throw Error('ID de recurso inválido.');
    const set = this.resources.get(kind) ?? new Set<string>(); set.add(key); this.resources.set(kind, set);
    return key;
  }
  require(kind: Kind, value: unknown): void {
    if (!this.resources.get(kind)?.has(String(value))) throw Error('Recurso fuera del lote: operación bloqueada.');
  }
  snapshot(): Record<string, string[]> { return Object.fromEntries([...this.resources].map(([k,v])=>[k,[...v]])); }
}
// Se invoca antes de TODO envío. El admin existente solo puede abrir/cerrar su propia sesión.
export function guard(method: string, path: string, body: Record<string, unknown>, owned: Owned, testIdentity: boolean): void {
  const route = path.split('?')[0]!;
  if (method === 'GET') {
    if (route === '/carts/current' && !testIdentity) throw Error('Carrito ajeno bloqueado.');
    return;
  }
  if (['/auth/register','/auth/login','/auth/refresh','/auth/logout'].includes(route)) {
    if(method!=='POST')throw Error('Método de autenticación fuera del contrato.');
    if (route === '/auth/register' && (!testIdentity || typeof body.email !== 'string' || !body.email.endsWith('@example.invalid')))
      throw Error('Solo se registran cuentas ficticias del lote.');
    if(route==='/auth/register'&&owned.batch&&!(body.email as string).startsWith(`qa-${owned.batch.toLowerCase()}-`))
      throw Error('Correo de otro lote bloqueado.');
    if (route === '/auth/logout' && body.all !== false) throw Error('Revocación global bloqueada.');
    return;
  }
  if (/^\/checkouts\/expire$/.test(route)) throw Error('Expiración global bloqueada.');
  if (!testIdentity && (route === '/checkouts' || route.startsWith('/checkouts/') ||
      route === '/orders/payments' || /^\/orders\/\d+\/cancel$/.test(route) ||
      route === '/returns' || route === '/coupons/validate'))
    throw Error('La cuenta administrativa no opera como Cliente.');
  for (const [field,kind] of Object.entries({categoryId:'category',productId:'product',variantId:'variant',cartId:'cart',orderId:'order',addressId:'address'} as const))
    if (body[field] !== undefined && body[field] !== null) owned.require(kind,body[field]);
  if (Array.isArray(body.items)) for (const item of body.items) owned.require('line',(item as Record<string,unknown>).orderItemId);
  const target = route.match(/^\/(catalog\/(?:categories|products|variants)|users|coupons|checkouts|orders|returns)(?:\/)(\d+)/);
  if (target) {
    const kinds:Record<string,Kind>={'catalog/categories':'category','catalog/products':'product','catalog/variants':'variant',users:'user',coupons:'coupon',checkouts:'checkout',orders:'order',returns:'return'};
    owned.require(kinds[target[1]!]!,target[2]);
  }
  const address = route.match(/^\/users\/me\/addresses\/(\d+)$/);
  const image = route.match(/^\/catalog\/images\/(\d+)$/);
  if(image) owned.require('image',image[1]);
  if(address) owned.require('address',address[1]);
  if(route.startsWith('/carts/')) {
    if(!testIdentity) throw Error('Solo cuentas nuevas o invitados del lote pueden operar carritos.');
    const line=route.match(/^\/carts\/current\/items\/(\d+)$/); if(line) owned.require('variant',line[1]);
  }
  if(route === '/users/me' || route.startsWith('/users/me/')) {
    if(!testIdentity) throw Error('Cambios al administrador existente bloqueados.');
  }
  if(method === 'DELETE' && !/^\/carts\/current\/items(?:\/\d+)?$/.test(route)) throw Error('Eliminación bloqueada.');
  const allowed:Record<string,RegExp>={
    POST:/^(\/catalog\/(categories|products|variants|images)|\/inventory\/movements|\/coupons(\/validate)?|\/carts\/(current\/items|merge)|\/checkouts(\/\d+\/cancel)?|\/orders\/(payments|\d+\/cancel)|\/returns(\/\d+\/(complete|refunds|cancel|items))?|\/users\/me\/addresses)$/,
    PATCH:/^(\/catalog\/(categories|products|variants|images)\/\d+|\/coupons\/\d+(\/state)?|\/carts\/current\/items\/\d+|\/orders\/\d+\/state|\/returns\/\d+\/state|\/users\/(me(\/addresses\/\d+)?|\d+\/access))$/,
    DELETE:/^\/carts\/current\/items(\/\d+)?$/
  };
  if(!allowed[method]?.test(route)) throw Error('Método o ruta fuera del alcance de la suite.');
  if(owned.batch){
    const prefix='QA-'+owned.batch;
    if(route==='/catalog/categories'&&body.name!=='QA '+owned.batch)throw Error('Categoría de otro lote bloqueada.');
    if(route==='/catalog/products'&&body.description!==owned.batch)throw Error('Producto sin marca del lote.');
    if(route==='/catalog/variants'&&(typeof body.sku!=='string'||!body.sku.startsWith(prefix+'-')))throw Error('SKU de otro lote bloqueado.');
    if(route==='/coupons'&&(typeof body.code!=='string'||!(body.code===prefix||body.code.startsWith(prefix+'-'))))throw Error('Cupón de otro lote bloqueado.');
    if(route==='/inventory/movements'&&body.reason!==owned.batch)throw Error('Movimiento sin marca del lote.');
  }
}

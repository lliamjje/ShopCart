import {randomBytes,randomUUID} from 'node:crypto';
import {setTimeout as sleep} from 'node:timers/promises';
import {Context,type Scenario} from './context.js';
import {Client,check} from './client.js';
import {id,intId,object,rows,money} from '../support/values.js';
import {sqlErrors} from '../../src/repositories/sqlErrors.js';

export const extensionNames=['images','refunds','concurrency','expiry','jwt','expirations'] as const;
export type Extension=typeof extensionNames[number];

// Preparación mínima nueva, sin reutilizar IDs ni ejecutar los 33 escenarios.
async function fixture(c:Context,stock:number):Promise<void>{
  await c.guest.init();
  check(rows((await c.guest.call('GET',`/catalog/products?search=${c.batch}`)).products).length===0,'Lote ya existente.');
  const category=object((await c.admin.call('POST','/catalog/categories',{name:'QA '+c.batch,active:true},201)).category);
  c.ids.category=c.owned.add('category',intId(category.IdCategoria));
  const product={categoryId:Number(c.ids.category),name:'QA '+c.batch,description:c.batch,active:false};
  c.ids.product=c.owned.add('product',id(object((await c.admin.call('POST','/catalog/products',product,201)).product).IdProducto));
  const variant={productId:c.ids.product,sku:`QA-${c.batch}-EXT`,price:'112.0000',active:true};
  c.ids.m=c.owned.add('variant',id(object((await c.admin.call('POST','/catalog/variants',variant,201)).variant).IdVariante));
  if(stock)await c.admin.call('POST','/inventory/movements',{variantId:c.ids.m,type:'ENTRADA',quantity:stock,reason:c.batch,operationId:BigInt('0x'+randomBytes(7).toString('hex')).toString()},201);
  await c.admin.call('PATCH',`/catalog/products/${c.ids.product}`,{...product,active:true});
  const shipping=rows((await c.guest.call('GET','/shipping-methods')).shippingMethods).find(r=>r.Codigo==='RETIRO_TIENDA');
  check(shipping&&money(shipping.Costo)===0n,'Falta retiro gratuito activo.');c.ids.shipping=String(shipping.IdMetodoEnvio);
  check(Number((await c.balance()).CantidadFisica)===stock,'Saldo inicial inesperado.');
}

async function buyer(c:Context):Promise<Client>{const client=c.client(true);await client.init();return client;}
async function checkoutBody(c:Context,client:Client):Promise<Record<string,unknown>>{
  await c.cart(client);
  await client.call('POST','/carts/current/items',{variantId:c.ids.m,quantity:1});
  const cart=object((await c.cart(client)).cart);
  return {cartId:cart.IdCarrito,cartRevision:cart.RevisionCarrito,shippingMethodId:Number(c.ids.shipping),recipientName:'QA',phone:'55550000',department:'Guatemala',city:'Guatemala',address1:c.batch};
}

export async function imageScenario(c:Context):Promise<void>{
  await fixture(c,0);
  // Ruta de un fixture real. Este endpoint solo persiste metadatos, no sirve archivos.
  const body={productId:c.ids.product,path:'test/functional/fixtures/product.svg',alt:c.batch,displayOrder:0,primary:true,active:true};
  const image=id(object((await c.admin.call('POST','/catalog/images',body,201)).image).IdImagen);
  c.owned.add('image',image);
  const images=async()=>rows((await c.guest.call('GET',`/catalog/products/${c.ids.product}`)).images);
  const stored=(await images()).find(r=>r.IdImagen===image);
  check(stored&&stored.RutaImagen===body.path&&stored.TextoAlternativo===c.batch&&stored.EsPrincipal===true,'Metadatos de imagen incorrectos.');
  await c.admin.call('PATCH',`/catalog/images/${image}`,{...body,active:false});
  check(!(await images()).some(r=>r.IdImagen===image),'Imagen inactiva visible públicamente.');
}

export async function refundScenario(c:Context):Promise<void>{
  await fixture(c,1);const client=await buyer(c);
  const order=await c.checkout('extended',client,false,c.ids.m,1);
  await client.call('POST','/orders/payments',{orderId:order.orderId,action:'APROBAR'},200,c.key('pay'));
  for(const state of ['EN_PREPARACION','ENVIADO','ENTREGADO'])await c.admin.call('PATCH',`/orders/${order.orderId}/state`,{state,note:c.batch});
  const line=rows((await c.order(client,order.orderId)).items)[0]!;
  const returnId=c.owned.add('return',id(object((await client.call('POST','/returns',{orderId:order.orderId,items:[{orderItemId:line.IdDetallePedido,quantity:1}],reason:c.batch},201,randomUUID())).return).IdDevolucion));
  for(const state of ['APROBADA','RECIBIDA'])await c.admin.call('PATCH',`/returns/${returnId}/state`,{state,note:c.batch});
  const firstKey=c.key('refund');
  await c.admin.call('POST',`/returns/${returnId}/complete`,{},200,firstKey);
  const first=object((await c.admin.call('POST',`/returns/${returnId}/refunds`,{action:'RECHAZAR'},200,firstKey)).refund);
  check(first.Estado==='RECHAZADO','No se rechazó el primer reembolso.');
  const nextKey=c.key('refund_new');
  const next=object((await c.admin.call('POST',`/returns/${returnId}/refunds`,{action:'APROBAR'},200,nextKey)).refund);
  check(next.Estado==='APROBADO'&&next.IdReembolso!==first.IdReembolso&&money(next.Monto)===1120000n,'Nuevo intento incorrecto.');
  const history=rows((await client.call('GET',`/orders/${order.orderId}/returns`)).refunds);
  check(history.length===2&&history.filter(r=>r.Estado==='APROBADO').length===1&&history.filter(r=>r.Estado==='RECHAZADO').length===1,'Historial monetario incorrecto.');
  check(Number((await c.balance()).CantidadFisica)===1,'Reembolso volvió a reintegrar stock.');
}

export async function raceScenario(c:Context):Promise<void>{
  await fixture(c,1);
  const clients=[await buyer(c),await buyer(c)];
  const bodies=[await checkoutBody(c,clients[0]!),await checkoutBody(c,clients[1]!)];
  // Dos solicitudes únicas y ya preparadas. Esperar AMBAS incluso ante transporte incierto.
  const outcomes=await Promise.allSettled(clients.map((client,i)=>client.raw('POST','/checkouts',bodies[i]!,c.key('race'))));
  const replies=outcomes.filter(r=>r.status==='fulfilled').map(r=>r.value);
  for(const reply of replies)if(reply.status===201){
    const checkout=object(object(reply.body.data).checkout);
    c.owned.add('checkout',id(checkout.IdCheckout));c.owned.add('order',id(checkout.IdPedido));
  }
  check(outcomes.every(r=>r.status==='fulfilled'),'Carrera con resultado incierto; revisar ambas operaciones, sin reintentar.');
  check(replies.filter(r=>r.status===201&&r.body.success===true).length===1&&replies.filter(r=>r.status===409&&r.body.success===false).length===1,'Se esperaba un checkout y un conflicto de disponibilidad.');
  check(object(replies.find(r=>r.status===409)!.body.error).code==='SQL_62710','El conflicto no corresponde a inventario insuficiente.');
  const balance=await c.balance();
  check(Number(balance.CantidadFisica)===1&&Number(balance.CantidadReservada)===1&&Number(balance.Disponible)===0,'Sobreventa o reserva incorrecta.');
}

// Solo se invoca en modos prolongados explícitos. No cambia ningún reloj.
export async function waitUntil(deadline:number,log:(remaining:number)=>void,now=Date.now,pause:(ms:number)=>Promise<unknown>=sleep):Promise<void>{
  check(Number.isFinite(deadline)&&deadline-now()<=17*60000,'Plazo temporal fuera del límite seguro.');
  for(;;){const remaining=deadline-now();if(remaining<=0)return;log(Math.ceil(remaining/1000));await pause(Math.min(30000,remaining));}
}
async function prepareReservation(c:Context):Promise<{client:Client;checkoutId:string;deadline:number}>{
  await fixture(c,1);const client=await buyer(c);
  const order=await c.checkout('expiry',client,false,c.ids.m,1);
  // SQL fija 15 minutos antes de devolver la respuesta. Esperar desde su recepción
  // es conservador y no exige sincronizar los relojes SQL/Node.
  const deadline=Date.now()+15*60000+2000;
  check(Number((await c.balance()).Disponible)===0,'No se estableció la reserva inicial.');
  return {client,checkoutId:order.id,deadline};
}
async function verifyReservation(c:Context,reservation:Awaited<ReturnType<typeof prepareReservation>>):Promise<void>{
  c.owned.require('checkout',reservation.checkoutId);c.owned.require('variant',c.ids.m);
  const detail=await reservation.client.call('GET',`/checkouts/${reservation.checkoutId}`);
  check(object(detail.checkout).EstaVigente===false,'Checkout sigue vigente tras el plazo.');
  // El JWT administrativo ya puede haber expirado. Consultar catálogo público,
  // sin renovar sesiones ni introducir escrituras durante la espera.
  const variant=rows((await c.guest.call('GET',`/catalog/products/${c.ids.product}`)).variants).find(r=>r.IdVariante===c.ids.m);
  check(variant&&Number(variant.Disponible)===1,'La reserva vencida sigue consumiendo disponibilidad.');
  // No exigir Estado=EXPIRADA: la disponibilidad depende de estado Y tiempo.
  check(rows(detail.inventoryReservations).length===1,'Historial de reserva perdido.');
}
export async function expiryScenario(c:Context,wait=waitUntil):Promise<void>{
  const reservation=await prepareReservation(c);
  await wait(reservation.deadline,seconds=>console.log(JSON.stringify({waiting:'reserva propia',seconds})));
  await verifyReservation(c,reservation);
}
async function prepareJwt(c:Context):Promise<{client:Client;deadline:number;token:string}>{
  const client=await c.register('jwt');
  const token=client.token;
  let exp:number;
  try{exp=JSON.parse(Buffer.from(token.split('.')[1]!,'base64url').toString('utf8')).exp;}catch{throw Error('Contrato JWT inválido.');}
  check(Number.isInteger(exp),'JWT sin expiración verificable.');
  await client.call('GET','/users/me');
  return {client,deadline:exp*1000+2000,token};
}
async function verifyJwt(jwt:Awaited<ReturnType<typeof prepareJwt>>):Promise<void>{
  check(jwt.client.token===jwt.token,'Se sustituyó el JWT original durante la espera.');
  const error=await jwt.client.call('GET','/users/me',{},401);
  check(error.code==='INVALID_ACCESS_TOKEN','El rechazo no corresponde al JWT expirado.');
}
export async function jwtScenario(c:Context,wait=waitUntil):Promise<void>{
  const jwt=await prepareJwt(c);
  await wait(jwt.deadline,seconds=>console.log(JSON.stringify({waiting:'JWT Cliente propio',seconds})));
  await verifyJwt(jwt);
}
export async function expirationsScenario(c:Context,wait=waitUntil):Promise<void>{
  // JWT y reserva tienen identidades distintas; el checkout invitado sigue siendo
  // consultable cuando ya vencieron los JWT del Cliente y del Administrador.
  const jwt=await prepareJwt(c);
  const reservation=await prepareReservation(c);
  const checks=[{deadline:jwt.deadline,label:'JWT Cliente propio',verify:()=>verifyJwt(jwt)},
    {deadline:reservation.deadline,label:'reserva propia',verify:()=>verifyReservation(c,reservation)}]
    .sort((a,b)=>a.deadline-b.deadline);
  for(const item of checks){
    await wait(item.deadline,seconds=>console.log(JSON.stringify({waiting:item.label,seconds})));
    await item.verify(); // Un fallo detiene el segundo chequeo; no hay escrituras tras la espera.
    console.log(JSON.stringify({expiration:item.label,result:'APROBADA'}));
  }
}
export function extendedPlan(name:string):Scenario[]{
  check(extensionNames.includes(name as Extension),'Escenario nuevo desconocido.');
  const run={images:imageScenario,refunds:refundScenario,concurrency:raceScenario,expiry:expiryScenario,jwt:jwtScenario,expirations:expirationsScenario}[name as Extension];
  const pending=name==='concurrency'&&sqlErrors[62710]?.status!==409
    ?'Bloqueada antes de crear fixtures: SQL 62710 no está mapeado a HTTP 409; producción devuelve 503. Corregir y reiniciar la API antes de ejecutar.'
    :undefined;
  return [{module:'extended',name,run,...(pending?{pending}:{})}];
}

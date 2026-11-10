import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { object,rows,money } from '../../support/values.js';
export const checkout:Scenario[]=[
 {module:'checkout',name:'Checkout, reservas, IVA incluido e idempotencia',requires:['coupons'],run:async c=>{
   const a=c.user('a'),before=Number((await c.balance()).Disponible);
   const order=await c.checkout('cancel',a);
   const repeat=object((await a.call('POST','/checkouts',order.body,201,order.key)).checkout);
   check(repeat.IdCheckout===order.id&&repeat.IdPedido===order.orderId,'Checkout duplicado.');
   await a.call('POST','/checkouts',{...order.body,address1:'Solicitud distinta'},409,order.key);
   const detail=await a.call('GET',`/checkouts/${order.id}`);
   check(object(detail.checkout).Estado==='RESERVADO','Checkout no reservado.');
   check(rows(detail.inventoryReservations).filter(r=>r.Estado==='ACTIVA').length===1,'Reserva de inventario incorrecta.');
   check(rows(detail.couponReservations).filter(r=>r.Estado==='ACTIVA').length===1,'Reserva de cupón incorrecta.');
   check(Number((await c.balance()).Disponible)===before-2,'La reserva no descuenta disponibilidad.');
   const historical=await c.order(a,order.orderId), header=object(historical.order),line=rows(historical.items)[0]!;
   check(money(header.Subtotal)===2240000n&&money(header.Descuento)===224000n&&money(header.Total)===2016000n,'Totales de checkout incorrectos.');
   check(money(line.BaseImponibleLinea)===1800000n&&money(line.MontoIVALinea)===216000n,'IVA incluido calculado incorrectamente.');
   check(money(line.BaseImponibleLinea)+money(line.MontoIVALinea)===money(line.TotalLinea),'Desglose fiscal no cuadra.');
   await c.user('b').call('GET',`/checkouts/${order.id}`,{},403);
   await a.call('PATCH',`/carts/current/items/${c.ids.m}`,{quantity:1},409);
 }},
 {module:'checkout',name:'Checkout invitado, tarifa real de envío y liberación',run:async c=>{
   const guest=c.client(true);await guest.init();
   const before=Number((await c.balance(c.ids.org)).Disponible);
   const order=await c.checkout('guest',guest,false,c.ids.org,1,c.ids.standard);
   const historical=object((await c.order(guest,order.orderId)).order);
   const shipping=money(c.values.standard!.Costo);
   check(money(historical.CostoEnvio)===shipping&&money(historical.Total)===560000n+shipping,'Tarifa fija no conservada.');
   await guest.call('POST',`/checkouts/${order.id}/cancel`);
   check(object((await guest.call('GET',`/checkouts/${order.id}`)).checkout).Estado==='CANCELADO','No se canceló checkout propio.');
   check(Number((await c.balance(c.ids.org)).Disponible)===before,'No se liberó la reserva.');
 }}
];

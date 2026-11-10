import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { object,rows,money } from '../../support/values.js';
export const payments:Scenario[]=[
 {module:'payments',name:'Pago pendiente y rechazo idempotente sin salida física',requires:['checkout'],run:async c=>{
   const a=c.user('a'),order=c.checkouts.cancel!;
   const key=c.key('decline');c.ids.declineKey=key;
   const body={orderId:order.orderId,action:'CREAR'};
   check(object((await a.call('POST','/orders/payments',body,200,key)).payment).Estado==='PENDIENTE','Pago no pendiente.');
   const first=object((await a.call('POST','/orders/payments',{...body,action:'RECHAZAR'},200,key)).payment);
   const repeated=object((await a.call('POST','/orders/payments',{...body,action:'RECHAZAR'},200,key)).payment);
   check(first.Estado==='RECHAZADO'&&first.IdPago===repeated.IdPago,'Rechazo no idempotente.');
   check(Number((await c.balance()).CantidadFisica)===10,'El rechazo alteró el saldo físico.');
 }},
 {module:'payments',name:'Aprobación única consume stock y cupón una sola vez',run:async c=>{
   const a=c.user('a'),order=c.checkouts.cancel!,key=c.key('approve');
   const body={orderId:order.orderId,action:'APROBAR'};
   const first=object((await a.call('POST','/orders/payments',body,200,key)).payment);
   const repeated=object((await a.call('POST','/orders/payments',body,200,key)).payment);
   check(first.Estado==='APROBADO'&&first.IdPago===repeated.IdPago&&money(first.Monto)===2016000n,'Aprobación no idempotente.');
   const historical=await c.order(a,order.orderId);
   check(object(historical.order).Estado==='PAGADO'&&rows(historical.payments).filter(r=>r.Estado==='APROBADO').length===1,'Estado/pago duplicado.');
   check(Number((await c.balance()).CantidadFisica)===8,'Stock físico incorrecto tras pago.');
   const uses=rows((await c.admin.call('GET',`/coupons/${c.ids.coupon}/uses`)).uses);
   check(uses.filter(r=>r.IdPedido===order.orderId).length===1,'Uso de cupón duplicado.');
   await a.call('POST','/orders/payments',{...body,amount:'0'},400,key);
 }}
];

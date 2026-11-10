import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { object,rows,money } from '../../support/values.js';
export const orders:Scenario[]=[
 {module:'orders',name:'Consulta propia, propiedad y cancelación idempotente',requires:['payments'],run:async c=>{
   const a=c.user('a'),order=c.checkouts.cancel!;
   await c.user('b').call('GET',`/orders/${order.orderId}`,{},403);
   check(rows((await a.call('GET','/orders')).orders).some(r=>r.IdPedido===order.orderId),'Pedido no listado.');
   const key=c.key('cancel');
   for(let attempt=0;attempt<2;attempt++){
     const result=await a.call('POST',`/orders/${order.orderId}/cancel`,{},200,key);
     check(object(result.order).Estado==='CANCELADO','Pedido no cancelado.');
     const refunds=rows(result.refunds);check(refunds.length===1&&money(refunds[0]!.Monto)===2016000n,'Reembolso de cancelación duplicado o incorrecto.');
   }
   check(Number((await c.balance()).CantidadFisica)===10,'Cancelación no reintegró existencias exactamente una vez.');
   // Los usos no se restituyen al cancelar: comprueba el límite por usuario.
   await c.cart(a);await a.call('POST','/carts/current/items',{variantId:c.ids.m,quantity:1});
   const cart=object((await c.cart(a)).cart);
   await a.call('POST','/coupons/validate',{cartId:cart.IdCarrito,code:c.ids.couponCode},409);
   await a.call('DELETE','/carts/current/items');
 }},
 {module:'orders',name:'Nuevo pedido Cliente y transiciones del Operador',run:async c=>{
   const b=c.user('b'),order=await c.checkout('return',b);
   await b.call('POST','/orders/payments',{orderId:order.orderId,action:'APROBAR'},200,c.key('pay_return'));
   await b.call('PATCH',`/orders/${order.orderId}/state`,{state:'EN_PREPARACION'},403);
   for(const state of ['EN_PREPARACION','ENVIADO','ENTREGADO'])await c.user('operator').call('PATCH',`/orders/${order.orderId}/state`,{state,note:c.batch});
   const historical=await c.order(b,order.orderId);
   check(object(historical.order).Estado==='ENTREGADO'&&rows(historical.history).length>=5,'Falta estado o historial.');
   await b.call('POST',`/orders/${order.orderId}/cancel`,{},409,c.key('late_cancel'));
 }}
];

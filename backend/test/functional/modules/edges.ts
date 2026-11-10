import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { id,object,rows,money } from '../../support/values.js';
export const edges:Scenario[]=[
 {module:'edges',name:'Pedido gratuito con aprobación Q0 y cancelación sin reembolso monetario',requires:['reports'],run:async c=>{
   const code='QA-'+c.batch+'-ZERO';
   c.owned.add('coupon',id(object((await c.admin.call('POST','/coupons',{...c.values.coupon,code,value:'100.0000',userLimit:null},201)).coupon).IdCupon));
   const previous=c.ids.couponCode;c.ids.couponCode=code;
   const a=c.user('a'),order=await c.checkout('zero',a);c.ids.couponCode=previous!;
   const payment=object((await a.call('POST','/orders/payments',{orderId:order.orderId,action:'APROBAR'},200,c.key('zero'))).payment);
   check(payment.Estado==='APROBADO'&&money(payment.Monto)===0n,'Pago gratuito inválido.');
   const result=await a.call('POST',`/orders/${order.orderId}/cancel`,{},200,c.key('zero_cancel'));
   check(rows(result.refunds).length===0,'Un pedido gratuito no debe generar movimiento monetario.');
 }},
 {module:'edges',name:'Redondeo de porcentaje y coherencia del desglose fiscal',run:async c=>{
   const code='QA-'+c.batch+'-ROUND';
   c.owned.add('coupon',id(object((await c.admin.call('POST','/coupons',{...c.values.coupon,code,value:'33.3333',userLimit:null},201)).coupon).IdCupon));
   const previous=c.ids.couponCode;c.ids.couponCode=code;
   const a=c.user('a'),order=await c.checkout('round',a,true,c.ids.m,3);c.ids.couponCode=previous!;
   const historical=await c.order(a,order.orderId),header=object(historical.order),line=rows(historical.items)[0]!;
   check(money(header.Descuento)===1119999n&&money(header.Total)===2240001n,'Redondeo a cuatro decimales incorrecto.');
   check(money(line.TotalLinea)===money(header.Total)&&money(line.BaseImponibleLinea)+money(line.MontoIVALinea)===money(line.TotalLinea),'Desglose fiscal no conserva importes.');
   await a.call('POST',`/checkouts/${order.id}/cancel`);
 }},
 {module:'edges',name:'Límite global ocupado por reserva y liberación posterior',run:async c=>{
   const code='QA-'+c.batch+'-CAP';
   c.owned.add('coupon',id(object((await c.admin.call('POST','/coupons',{...c.values.coupon,code,globalLimit:1,userLimit:null},201)).coupon).IdCupon));
   const previous=c.ids.couponCode;c.ids.couponCode=code;
   const a=c.user('a'),b=c.user('b'),order=await c.checkout('cap',a);c.ids.couponCode=previous!;
   await c.cart(b);await b.call('POST','/carts/current/items',{variantId:c.ids.m,quantity:1});
   const cartId=object((await c.cart(b)).cart).IdCarrito;
   await b.call('POST','/coupons/validate',{cartId,code},409);
   await a.call('POST',`/checkouts/${order.id}/cancel`);
   object((await b.call('POST','/coupons/validate',{cartId,code})).quote);
   await b.call('DELETE','/carts/current/items');
 }}
];

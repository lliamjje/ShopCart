import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { id,object,money } from '../../support/values.js';
export const coupons:Scenario[]=[
 {module:'coupons',name:'Cupón propio, cotización y errores de vigencia/mínimo',requires:['carts'],run:async c=>{
   const a=c.user('a');await c.cart(a);
   await a.call('POST','/carts/current/items',{variantId:c.ids.m,quantity:2});
   const cartId=id(object((await c.cart(a)).cart).IdCarrito);
   const body={code:'QA-'+c.batch,type:'PORCENTAJE',value:'10.0000',minimum:'1.0000',startsAt:c.from,endsAt:c.to,categoryId:Number(c.ids.category),globalLimit:3,userLimit:1,active:true,description:'Lote QA'};
   c.ids.couponCode=body.code;c.values.coupon=body;
   c.ids.coupon=c.owned.add('coupon',id(object((await c.admin.call('POST','/coupons',body,201)).coupon).IdCupon));
   const quote=object((await a.call('POST','/coupons/validate',{cartId,code:body.code})).quote);
   check(money(quote.Descuento)===224000n,'Descuento del diez por ciento incorrecto.');
   await a.call('POST','/coupons/validate',{cartId,code:'NO-'+c.batch},404);
   for(const [label,override] of [
     ['MIN',{minimum:'999.0000'}],
     ['EXP',{startsAt:new Date(Date.now()-172800000).toISOString(),endsAt:new Date(Date.now()-86400000).toISOString()}]
   ] as const){
     const code='QA-'+c.batch+'-'+label;
     c.owned.add('coupon',id(object((await c.admin.call('POST','/coupons',{...body,...override,code},201)).coupon).IdCupon));
     await a.call('POST','/coupons/validate',{cartId,code},409);
   }
 }},
 {module:'coupons',name:'Descuento fijo y total no negativo',run:async c=>{
   const body={...c.values.coupon,code:'QA-'+c.batch+'-FIX',type:'MONTO_FIJO',value:'999.0000',userLimit:null};
   c.owned.add('coupon',id(object((await c.admin.call('POST','/coupons',body,201)).coupon).IdCupon));
   const a=c.user('a'),cartId=id(object((await c.cart(a)).cart).IdCarrito);
   const quote=object((await a.call('POST','/coupons/validate',{cartId,code:body.code})).quote);
   check(money(quote.Descuento)===money(quote.Subtotal),'El descuento fijo debe limitarse al subtotal elegible.');
 }}
];

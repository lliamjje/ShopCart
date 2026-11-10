import { randomUUID } from 'node:crypto';
import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { id,object,rows,money } from '../../support/values.js';
export const returns:Scenario[]=[
 {module:'returns',name:'Devolución parcial idempotente y capacidad ocupada',requires:['orders'],run:async c=>{
   const b=c.user('b'),order=c.checkouts.return!;
   const historical=await c.order(b,order.orderId),line=rows(historical.items)[0]!;
   const body={orderId:order.orderId,items:[{orderItemId:line.IdDetallePedido,quantity:1}],reason:c.batch};
   const key=randomUUID();
   c.ids.return=c.owned.add('return',id(object((await b.call('POST','/returns',body,201,key)).return).IdDevolucion));
   const repeat=object((await b.call('POST','/returns',body,201,key)).return);
   check(repeat.IdDevolucion===c.ids.return,'Solicitud duplicada.');
   await b.call('POST','/returns',{...body,items:[{orderItemId:line.IdDetallePedido,quantity:2}]},409,randomUUID());
   await c.user('a').call('POST','/returns',body,403,randomUUID());
 }},
 {module:'returns',name:'Recepción, reintegro y reembolso simulado idempotentes',run:async c=>{
   const op=c.user('operator'),returnId=c.ids.return!,before=Number((await c.balance()).CantidadFisica);
   for(const state of ['APROBADA','RECIBIDA'])await op.call('PATCH',`/returns/${returnId}/state`,{state,note:c.batch});
   const key=c.key('refund');
   for(let attempt=0;attempt<2;attempt++){
     const result=await op.call('POST',`/returns/${returnId}/complete`,{},200,key);
     check(money(object(result.return).MontoReembolsable)===1008000n&&rows(result.refunds).length===1,'Importe o cantidad de reembolsos incorrectos.');
   }
   check(Number((await c.balance()).CantidadFisica)===before+1,'Reintegro duplicado.');
   for(let attempt=0;attempt<2;attempt++)check(object((await op.call('POST',`/returns/${returnId}/refunds`,{action:'APROBAR'},200,key)).refund).Estado==='APROBADO','Reembolso no aprobado.');
   const result=await c.user('b').call('GET',`/orders/${c.checkouts.return!.orderId}/returns`);
   check(rows(result.returns).some(r=>r.IdDevolucion===returnId&&r.Estado==='COMPLETADA'),'Devolución no completada.');
   check(rows(result.refunds).filter(r=>r.Estado==='APROBADO').length===1,'Reembolso duplicado.');
 }}
];

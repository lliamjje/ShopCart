import { randomBytes } from 'node:crypto';
import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { id,object,rows } from '../../support/values.js';
export const inventory:Scenario[]=[
 {module:'inventory',name:'ENTRADA propia, kardex y saldo',requires:['catalog'],run:async c=>{
   for(const [variant,quantity] of [['m',10],['org',5]] as const){
     const body={variantId:c.ids[variant],type:'ENTRADA',quantity,reason:c.batch,operationId:BigInt('0x'+randomBytes(7).toString('hex')).toString()};
     const movement=object((await c.user('operator').call('POST','/inventory/movements',body,201)).movement);
     c.ids['movement_'+variant]=id(movement.IdMovimiento);c.values['movement_'+variant]=body;
     const balance=await c.balance(c.ids[variant]);check(Number(balance.CantidadFisica)===quantity&&Number(balance.Disponible)===quantity,'Saldo o disponible incorrecto.');
   }
   const movements=rows((await c.user('operator').call('GET',`/inventory/movements?${c.interval()}&variantId=${c.ids.m}`)).movements);
   check(movements.filter(m=>m.IdMovimiento===c.ids.movement_m).length===1,'Falta el movimiento en kardex.');
 }},
 {module:'inventory',name:'Repetición explícita idempotente de movimiento',run:async c=>{
   // Repetición deliberada de una operación YA confirmada, con el mismo operationId.
   const again=object((await c.user('operator').call('POST','/inventory/movements',c.values.movement_m,201)).movement);
   check(again.IdMovimiento===c.ids.movement_m&&Number((await c.balance()).CantidadFisica)===10,'Se duplicó la entrada.');
 }}
];

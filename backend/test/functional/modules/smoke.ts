import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { rows,money } from '../../support/values.js';
export const smoke:Scenario[]=[
 {module:'smoke',name:'HTTP y conexión SQL real',run:async c=>{
   const health=await c.guest.call('GET','/health?database=true');check(health.database==='connected','SQL no está conectado.');
 }},
 {module:'smoke',name:'Categorías, envíos y validaciones públicas',run:async c=>{
   rows((await c.guest.call('GET','/catalog/categories')).categories);
   const shipping=rows((await c.guest.call('GET','/shipping-methods')).shippingMethods);
   const free=shipping.find(r=>r.Codigo==='RETIRO_TIENDA');check(free&&money(free.Costo)===0n,'Falta retiro gratuito.');
   c.ids.shipping=String(free.IdMetodoEnvio);
   const standard=shipping.find(r=>r.Codigo==='ESTANDAR');check(standard,'Falta envío estándar.');
   c.ids.standard=String(standard.IdMetodoEnvio);c.values.standard=standard;
   await c.guest.call('GET','/catalog/products/abc',{},400);
   await c.guest.call('GET','/catalog/products?pageSize=101',{},400);
   await c.guest.call('GET','/catalog/products?minPrice=20&maxPrice=10',{},400);
   await c.guest.call('GET','/qa-functional-missing',{},404);
 }}
];

import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { id,object,rows,money } from '../../support/values.js';
export const carts:Scenario[]=[
 {module:'carts',name:'Carrito Cliente: agregar, fijar, quitar y validar disponibilidad',requires:['publication'],run:async c=>{
   const a=c.user('a');const cart=await c.cart(a);
   await a.call('POST','/carts/current/items',{variantId:c.ids.m,quantity:2});
   await a.call('PATCH',`/carts/current/items/${c.ids.m}`,{quantity:3});
   const changed=await c.cart(a);check(money(object(changed.totals).Subtotal)===3360000n,'Subtotal incorrecto.');
   await a.call('PATCH',`/carts/current/items/${c.ids.m}`,{quantity:11},409);
   await a.call('POST','/carts/current/items',{variantId:c.ids.l,quantity:1},409);
   await a.call('PATCH',`/carts/current/items/${c.ids.m}`,{quantity:0},400);
   await c.user('b').call('GET',`/carts/${id(object(cart.cart).IdCarrito)}`,{},403);
   await a.call('DELETE',`/carts/current/items/${c.ids.m}`);check(rows((await c.cart(a)).items).length===0,'No se quitó la línea.');
 }},
 {module:'carts',name:'Invitado y fusión con Cliente del lote',run:async c=>{
   await c.cart(c.guest);check(!!c.guest.cookie('sc_guest'),'Falta cookie invitado.');
   await c.guest.call('POST','/carts/current/items',{variantId:c.ids.org,quantity:1});
   const b=c.user('b');c.guest.token=b.token;
   await c.guest.call('POST','/carts/merge');c.guest.token='';
   check(rows((await c.cart(b)).items).some(r=>r.IdVariante===c.ids.org),'La fusión no conservó la línea.');
   await b.call('DELETE','/carts/current/items');
 }}
];

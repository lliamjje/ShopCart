import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { id,object,rows } from '../../support/values.js';
export const users:Scenario[]=[
 {module:'users',name:'Perfil y dirección propios; pertenencia de dirección',requires:['auth'],run:async c=>{
   const a=c.user('a');await a.call('PATCH','/users/me',{firstName:'QA actualizado',lastName:'Cliente A'});
   check(object((await a.call('GET','/users/me')).profile).Nombre==='QA actualizado','No se actualizó el perfil propio.');
   const address={recipientName:'QA',phone:'55550000',department:'Guatemala',city:'Guatemala',address1:'Prueba QA',primary:true,active:true};
   c.ids.address=c.owned.add('address',id(object((await a.call('POST','/users/me/addresses',address,201)).address).IdDireccion));
   check(rows((await a.call('GET','/users/me/addresses')).addresses).some(r=>r.IdDireccion===c.ids.address),'No aparece la dirección.');
   await c.user('b').call('PATCH',`/users/me/addresses/${c.ids.address}`,address,403);
 }},
 {module:'users',name:'Operador creado por flujo administrativo; RBAC',run:async c=>{
   const op=await c.register('operator');
   // Si RBAC estuviera roto, esta comprobación no concedería privilegios nuevos.
   await c.user('a').call('PATCH',`/users/${op.userId}/access`,{role:'Cliente',active:true},403);
   await c.admin.call('PATCH',`/users/${op.userId}/access`,{role:'Operador',active:true});
   op.token='';await op.login(op.email,op.password,'Operador');
   rows((await op.call('GET','/inventory')).inventory);
   await op.call('POST','/catalog/categories',{name:'QA '+c.batch,active:true},403);
 }},
 {module:'users',name:'Desactivación de cuenta propia del lote revoca acceso',run:async c=>{
   const disabled=await c.register('disabled');
   await c.admin.call('PATCH',`/users/${disabled.userId}/access`,{role:'Cliente',active:false});
   await disabled.call('GET','/users/me',{},401);disabled.token='';
   await disabled.call('POST','/auth/login',{email:disabled.email,password:disabled.password},401);
 }}
];

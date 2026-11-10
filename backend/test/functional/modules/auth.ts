import { check } from '../client.js';
import { object } from '../../support/values.js';
import type { Scenario } from '../context.js';
import { expectedAdminId } from '../config.js';
export const auth:Scenario[]=[
 {module:'auth',name:'Administrador legítimo y perfil SQL',requires:['smoke'],run:async c=>{
   check(c.admin.userId===expectedAdminId,'La cuenta administrativa no corresponde al ID aprobado.');
   const profile=object((await c.admin.call('GET','/users/me')).profile);
   check(profile.IdUsuario===expectedAdminId&&profile.Rol==='Administrador','Perfil administrativo incorrecto.');
 }},
 {module:'auth',name:'Registro y login de dos Clientes temporales',run:async c=>{
   for(const label of ['a','b']){
     const user=await c.register(label), profile=object((await user.call('GET','/users/me')).profile);
     check(profile.IdUsuario===user.userId&&profile.Rol==='Cliente','Identidad Cliente incorrecta.');
   }
 }},
 {module:'auth',name:'CSRF, JWT alterado y acceso anónimo',run:async c=>{
   const noCsrf=await c.guest.raw('POST','/auth/login',{},undefined,{csrf:false});
   check(noCsrf.status===403,'Login sin CSRF debe rechazarse.');
   await c.guest.call('GET','/inventory',{},401);
   const a=c.user('a'), old=a.token;
   const response=await a.raw('GET','/users/me',{},undefined,{authorization:old.slice(0,-8)+'INVALIDX'});
   check(response.status===401,'JWT alterado debe devolver 401.');
   await a.call('GET','/audit',{},403);
 }},
 {module:'auth',name:'Registro duplicado y credenciales incorrectas',run:async c=>{
   const a=c.user('a');
   await a.call('POST','/auth/register',{firstName:'QA',lastName:'Duplicado',email:a.email,password:a.password},409);
   await c.guest.call('POST','/auth/login',{email:a.email,password:a.password+'incorrecta'},401);
 }}
];
export const sessions:Scenario[]=[
 {module:'sessions',name:'Rotación refresh y detección de reutilización',requires:['edges'],run:async c=>{
   const a=c.user('a'),old=a.cookie('sc_refresh');
   const renewed=await a.call('POST','/auth/refresh');
   check(typeof renewed.accessToken==='string'&&a.cookie('sc_refresh')!==old,'Refresh no rotó.');a.token=renewed.accessToken;
   await a.call('GET','/users/me/session');
   const replay=c.client(true);await replay.init();
   const result=await replay.raw('POST','/auth/refresh',{},undefined,{cookie:'sc_refresh='+old});
   check(result.status===401,'Reutilización de refresh debe rechazarse.');
   await a.call('GET','/users/me',{},401);a.token='';
 }},
 {module:'sessions',name:'Logout invalida sesión y JWT',run:async c=>{
   const b=c.user('b');await b.call('POST','/auth/logout',{all:false});
   await b.call('GET','/users/me',{},401);b.token='';
   // Cierre del Operador temporal; la sesión administrativa queda independiente.
   for(const client of [c.user('operator')]){
     await client.call('POST','/auth/logout',{all:false});client.token='';
   }
   const profile=object((await c.admin.call('GET','/users/me')).profile);
   check(profile.IdUsuario===expectedAdminId&&profile.Rol==='Administrador','Logout de Clientes afectó la sesión administrativa.');
 }}
];

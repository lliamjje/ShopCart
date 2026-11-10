import { test,after,mock } from 'node:test';
import assert from 'node:assert/strict';
import { readFile,readdir } from 'node:fs/promises';
import request from 'supertest';
import sql from 'mssql';
import argon2 from 'argon2';
import jwt from 'jsonwebtoken';
Object.assign(process.env,{NODE_ENV:'test',SQL_SERVER:'127.0.0.1',SQL_PORT:'1433',SQL_DATABASE:'ShopCart',
SQL_USER:'unit_test_only',SQL_PASSWORD:'unit-test-not-a-real-password',JWT_SECRET:'unit-test-only-secret-which-is-not-a-real-key',
SQL_ENCRYPT:'true',SQL_TRUST_SERVER_CERTIFICATE:'false',CORS_ORIGIN:'http://127.0.0.1:5173'});
const { createApp }=await import('../src/app.js');
const { closePool }=await import('../src/config/database.js');
const { procedures }=await import('../src/repositories/storedProcedures.js');
const { decimalInput,decimalOutput,bigintText }=await import('../src/utils/numeric.js');
const { accessToken,readAccess,idempotencyHash }=await import('../src/utils/tokens.js');
const { id,revision }=await import('../src/schemas/common.js');
const app=createApp(),agent=request.agent(app);
let connections=0,mode='missing';
let forcedSqlError: {number?:number;code?:string;originalError?:{info:{number:number}}}|undefined;
const calls:{name:string;params:Record<string,unknown>}[]=[];
function rows(values:Record<string,unknown>[],columns:Record<string,unknown>={}){return Object.assign(values,{columns});}
const fakePool={
 connected:true,close:async()=>undefined,
 request:()=>{const params:Record<string,unknown>={};return {
 input(name:string,_type:unknown,value:unknown){params[name]=value;return this;},
 output(){return this;},
 async execute(name:string){
 calls.push({name,params});
 if(forcedSqlError)throw Object.assign(new Error('SQL interno sensible que nunca debe aparecer en HTTP'),forcedSqlError);
 if(name==='dbo.SP_Seguridad_ConsultarPerfil')return {recordsets:[rows([{IdUsuario:'9007199254740993',Rol:'Cliente'}],{IdUsuario:{type:sql.BigInt}}),rows([])],output:{}};
 if(mode==='cart'&&name==='dbo.SP_Carritos_ObtenerActivo')return {recordsets:[rows([{IdCarrito:'9223372036854775807'}],{IdCarrito:{type:sql.BigInt}})],output:{}};
 if(mode==='cart'&&name==='dbo.SP_Carritos_Consultar')return {recordsets:[rows([{IdCarrito:'9223372036854775807',RevisionCarrito:'2026-11-02T12:00:00.1234567'}],{IdCarrito:{type:sql.BigInt}}),rows([]),rows([{Subtotal:0,Descuento:0}],{Subtotal:{type:sql.Decimal,scale:4},Descuento:{type:sql.Decimal,scale:4}})],output:{}};
 if(mode==='payment'&&name==='dbo.SP_Pedidos_Consultar')return {recordsets:[rows([{Total:12.3456}],{Total:{type:sql.Decimal,scale:4}}),rows([]),rows([]),rows([])],output:{}};
 if(mode==='payment'&&name==='dbo.SP_Pedidos_ProcesarPago')return {recordsets:[rows([{IdPago:'9007199254740994',Estado:'APROBADO',Monto:12.3456}],{IdPago:{type:sql.BigInt},Monto:{type:sql.Decimal,scale:4}})],output:{}};
 throw Object.assign(new Error('no mostrar contenido interno'),{number:2812});
 }};}
};
mock.method(sql.ConnectionPool.prototype,'connect',async()=>{connections++;return fakePool;});
after(async()=>{await closePool();mock.restoreAll();});
let csrf='';
test('HTTP inicia y health no consulta SQL',async()=>{
 const r=await agent.get('/api/v1/health');assert.equal(r.status,200);assert.equal(r.body.data.database,'not_connected');assert.equal(connections,0);
});
test('CSRF protege login y mutaciones, incluido origen no autorizado',async()=>{
 const no=await agent.post('/api/v1/auth/login').send({});assert.equal(no.status,403);assert.equal(connections,0);
 const c=await agent.get('/api/v1/auth/csrf');csrf=c.body.data.csrfToken;assert.equal(typeof csrf,'string');
 const bad=await agent.post('/api/v1/auth/login').set('X-CSRF-Token',csrf).set('Origin','https://evil.invalid').send({});
 assert.equal(bad.status,403);assert.equal(connections,0);
});
test('administración exige autenticación sin conectar al motor',async()=>{
 const r=await agent.get('/api/v1/inventory');assert.equal(r.status,401);assert.equal(connections,0);
});
test('no acepta identidad ni totales arbitrarios enviados por HTTP',async()=>{
 const r=await agent.post('/api/v1/checkouts').set('X-CSRF-Token',csrf).send({IdActor:'1',IdSesion:'arbitraria',total:'0'});
 assert.equal(r.status,400);assert.equal(connections,0);
 const p=await agent.get('/api/v1/catalog/products').query({pageSize:101});assert.equal(p.status,400);assert.equal(connections,0);
});
test('procedimientos no instalados devuelven 503 sin filtrar SQL',async()=>{
 const r=await agent.get('/api/v1/catalog/categories');assert.equal(r.status,503);
 assert.equal(r.body.error.code,'SQL_PROCEDURE_NOT_INSTALLED');assert.ok(!JSON.stringify(r.body).includes('no mostrar'));
});
test('carrito conserva bigint y usa un único secreto invitado por operación',async()=>{
 mode='cart';calls.length=0;
 const r=await agent.get('/api/v1/carts/current').set('X-CSRF-Token',csrf);
 assert.equal(r.status,200);assert.equal(r.body.data.cart.IdCarrito,'9223372036854775807');
 assert.equal(r.body.data.cart.RevisionCarrito,'2026-11-02T12:00:00.1234567');assert.equal(r.body.data.totals.Subtotal,'0.0000');
 assert.equal(calls.length,2);assert.ok(Buffer.isBuffer(calls[0]?.params.TokenInvitado));
 assert.deepEqual(calls[0]?.params.TokenInvitado,calls[1]?.params.TokenInvitado);
 const cookies=r.headers['set-cookie'] as unknown as string[];
 assert.ok(cookies.some(c=>c.startsWith('sc_guest=')&&c.includes('HttpOnly')));
 assert.ok(!JSON.stringify(r.body).includes('TokenInvitado'));
});
test('pago usa el total SQL e idempotencia estable; nunca acepta monto del navegador',async()=>{
 mode='payment';calls.length=0;
 const payload={orderId:'9007199254740993',action:'APROBAR'};
 const key='legitimate-retry-key-123456789';
 const first=await agent.post('/api/v1/orders/payments').set('X-CSRF-Token',csrf).set('Idempotency-Key',key).send(payload);
 assert.equal(first.status,200);assert.equal(first.body.data.payment.IdPago,'9007199254740994');
 assert.equal(first.body.data.payment.Monto,'12.3456');
 const payment=calls.find(c=>c.name==='dbo.SP_Pedidos_ProcesarPago');assert.equal(payment?.params.Monto,12.3456);
 const hash=payment?.params.ClaveOperacion;
 calls.length=0;
 const again=await agent.post('/api/v1/orders/payments').set('X-CSRF-Token',csrf).set('Idempotency-Key',key).send(payload);
 assert.equal(again.status,200);assert.deepEqual(calls.find(c=>c.name==='dbo.SP_Pedidos_ProcesarPago')?.params.ClaveOperacion,hash);
 const bad=await agent.post('/api/v1/orders/payments').set('X-CSRF-Token',csrf).set('Idempotency-Key',key).send({...payload,amount:'0'});
 assert.equal(bad.status,400);
});
test('JWT alterado o expirado no autentica; el actor no depende del rol declarado',async()=>{
 const token=accessToken({id:'9007199254740993',sessionId:'379720c8-2222-4222-8222-123456789012',role:'Administrador'});
 const claims=readAccess(token);assert.equal(claims.id,'9007199254740993');
 const r=await agent.get('/api/v1/inventory').set('Authorization','Bearer '+token);
 assert.equal(r.status,403); // El perfil SQL real del mock es Cliente.
 const expired=jwt.sign({sid:claims.sessionId},process.env.JWT_SECRET!,{subject:claims.id,issuer:'shopcart',audience:'shopcart-api',expiresIn:-1});
 assert.throws(()=>readAccess(expired));
 const wrong=await agent.get('/api/v1/users/me').set('Authorization','Bearer '+token.slice(0,-5)+'AAAAA');assert.equal(wrong.status,401);
});
test('tipos numéricos evitan pérdida silenciosa y conservan revisión SQL',()=>{
 assert.equal(bigintText('9223372036854775807'),'9223372036854775807');
 assert.throws(()=>bigintText(9007199254740992));assert.ok(id.safeParse('9223372036854775807').success);
 assert.ok(!id.safeParse('9223372036854775808').success);
 assert.equal(decimalInput('12.3456'),12.3456);assert.equal(decimalOutput(12.3456,4),'12.3456');
 assert.throws(()=>decimalInput('1000000000.0001'));assert.throws(()=>decimalOutput(1000000001,4));
 assert.ok(revision.safeParse('2026-11-02T12:00:00.1234567').success);
 assert.deepEqual(idempotencyHash('same-key','PAY'),idempotencyHash('same-key','PAY'));
 assert.notDeepEqual(idempotencyHash('same-key','PAY'),idempotencyHash('same-key','CANCEL'));
});
test('catálogo de firmas coincide con los 52 SP de las migraciones',async()=>{
 const dir=new URL('../../database/migrations/',import.meta.url);
 const files=(await readdir(dir)).filter(f=>/^(01[2-9]|020)_/.test(f));
 let count=0;
 for(const file of files){const text=await readFile(new URL(file,dir),'utf8');
 for(const m of text.matchAll(/CREATE PROCEDURE dbo\.(\w+)[\t ]*\r?\n([\s\S]*?)\r?\nAS/g)){
 const name=m[1] as keyof typeof procedures;assert.ok(procedures[name],name);
 const names=[...m[2]!.matchAll(/@(\w+)\s+(bigint|int|bit|tinyint|uniqueidentifier|nvarchar|varchar|datetime2|decimal|varbinary|binary)/g)].map(x=>x[1]);
 assert.deepEqual(procedures[name].params.map(p=>p.name),names);
 const signature=m[2]!.replaceAll("''","'");
 const actual=[...signature.matchAll(/@(\w+)\s+(bigint|int|bit|tinyint|uniqueidentifier|nvarchar|varchar|datetime2|decimal|varbinary|binary)(?:\((max|\d+)(?:,(\d+))?\))?(?:\s*=\s*(NULL|N?'[^']*'|\d+))?(?:\s+(OUTPUT))?/gi)]
 .map(p=>({name:p[1],type:p[2]?.toLowerCase(),size:p[3]??null,scale:p[4]??null,optional:p[5]!==undefined,output:!!p[6]}));
 assert.deepEqual(procedures[name].params,actual);count++;
 }}
 assert.equal(count,52);assert.equal(Object.keys(procedures).length,52);
});
test('Argon2id nativo calcula y verifica hashes sin SQL',async()=>{
 const hash=await argon2.hash('not-a-real-password',{type:argon2.argon2id,memoryCost:19456,timeCost:2,parallelism:1});
 assert.ok(hash.startsWith('$argon2id$'));assert.ok(await argon2.verify(hash,'not-a-real-password'));
 assert.ok(!await argon2.verify(hash,'wrong'));
});

test('inventario HTTP sin duplicados ni exposición de helpers internos',async()=>{
 const manifest=JSON.parse(await readFile(new URL('../api-contract.json',import.meta.url),'utf8'));
 const keys=manifest.endpoints.map((e:{method:string;path:string})=>e.method+' '+e.path);
 assert.equal(new Set(keys).size,keys.length);
 for(const e of manifest.endpoints)assert.ok(!String(e.procedure??'').startsWith('SP_Interno_'));
 assert.equal(manifest.endpointCount,keys.length);
});

test('identificador inválido responde 400 antes de invocar un procedimiento',async()=>{
 calls.length=0;
 for(const value of ['abc','0','-1','1.5','9223372036854775808']){
  const r=await agent.get('/api/v1/catalog/products/'+value);
  assert.equal(r.status,400);assert.equal(r.body.error.code,'VALIDATION_ERROR');
 }
 assert.equal(calls.length,0);
});

for(const [number,status] of [[62501,403],[62507,409],[62702,409],[62902,403],[62908,409],[62930,409]] as const){
 test(`SQL ${number} se traduce a HTTP ${status} sin filtrar mensajes internos`,async()=>{
  try{
   // Se prueba también el formato anidado del driver; no se invoca SQL Server.
   forcedSqlError=number%2?{number}:{originalError:{info:{number}}};
   const r=await agent.get('/api/v1/catalog/categories');
   assert.equal(r.status,status);assert.equal(r.body.success,false);
   assert.equal(r.body.error.code,'SQL_'+number);
   assert.ok(!JSON.stringify(r.body).includes('SQL interno sensible'));
  }finally{forcedSqlError=undefined;}
 });
}
for(const [label,error] of [
 ['permisos SQL',{number:229}],['timeout',{code:'ETIMEOUT'}],['error no reconocido',{number:99999}]
] as const){
 test(`fallo operativo ${label} conserva HTTP 503`,async()=>{
  try{
   forcedSqlError=error;
   const r=await agent.get('/api/v1/catalog/categories');
   assert.equal(r.status,503);assert.equal(r.body.success,false);
   assert.ok(!JSON.stringify(r.body).includes('SQL interno sensible'));
  }finally{forcedSqlError=undefined;}
 });
}

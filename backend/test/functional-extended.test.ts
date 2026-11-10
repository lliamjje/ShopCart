import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Context} from './functional/context.js';
import {guard,Owned} from './functional/safety.js';
import {extendedPlan,imageScenario,refundScenario,raceScenario,expiryScenario,jwtScenario,expirationsScenario,waitUntil} from './functional/extended.js';
import {sqlErrors} from '../src/repositories/sqlErrors.js';
import {executeScenarios} from './functional/execution.js';

test('selección nueva no ejecuta ninguno de los 33 escenarios anteriores',()=>{
  for(const name of ['images','refunds','concurrency','expiry','jwt','expirations']){
    const plan=extendedPlan(name);assert.equal(plan.length,1);assert.equal(plan[0]!.module,'extended');
    if(name!=='concurrency'||sqlErrors[62710]?.status===409)assert.equal(plan[0]!.pending,undefined);
    else assert.match(plan[0]!.pending!,/62710/);
  }
  assert.throws(()=>extendedPlan('all'));
});
test('carrera bloqueada por mapeo ausente se omite antes de cualquier HTTP',async()=>{
  assert.equal(sqlErrors[62710]?.status,409);
  assert.equal(extendedPlan('concurrency')[0]!.pending,undefined);
  const mapping=sqlErrors[62710]!;
  try{
    delete sqlErrors[62710];
    const plan=extendedPlan('concurrency');let started=false;
    const result=await executeScenarios(plan,new Context(()=>{throw Error('HTTP no permitido');}),()=>{started=true;});
    assert.equal(started,false);assert.equal(result.results[0]!.result,'OMITIDA');
  }finally{sqlErrors[62710]=mapping;}
});
test('imágenes: requiere imagen y producto propios antes de modificar',()=>{
  const owned=new Owned();owned.add('product','1');owned.add('image','2');
  guard('PATCH','/catalog/images/2',{productId:'1'},owned,false);
  assert.throws(()=>guard('PATCH','/catalog/images/3',{productId:'1'},owned,false));
  assert.throws(()=>guard('POST','/catalog/images',{productId:'4'},owned,false));
});
test('espera temporal: reloj controlado comprueba plazo y progreso sin esperar realmente',async()=>{
  let now=0;const pauses:number[]=[];const logs:number[]=[];
  await waitUntil(65000,n=>logs.push(n),()=>now,async ms=>{pauses.push(ms);now+=ms;});
  assert.deepEqual(pauses,[30000,30000,5000]);assert.deepEqual(logs,[65,35,5]);
  await assert.rejects(waitUntil(Infinity,()=>{}));
});

// Motor HTTP simulado, sin SQL/servidor. Verifica orquestación, no invariantes SQL.
async function simulated(kind:'images'|'refunds'|'concurrency'|'expiry'|'jwt'|'expirations',bad=false):Promise<void>{
  const original=globalThis.fetch;
  const c=new Context(()=>{});
  let stock=0,reserved=0,imageActive=false,expired=false,checkouts=0,cartCounter=0;
  const refunds:{IdReembolso:string;Estado:string;Monto:string}[]=[];
  const calls:string[]=[];const keys:string[]=[];
  globalThis.fetch=async(url,options)=>{
    const path=String(url).replace('http://127.0.0.1:3000/api/v1','');
    const method=options?.method;const headers=options?.headers as Record<string,string>;
    const body=options?.body?JSON.parse(String(options.body)):{};
    calls.push(`${method} ${path}`);
    const ok=(data:unknown,status=200,extra:Record<string,string>={})=>Response.json({success:true,data},{status,headers:extra});
    if(path==='/auth/csrf')return ok({csrfToken:'a'.repeat(43)},200,{'Set-Cookie':`sc_csrf=${'a'.repeat(43)}`});
    if(path==='/auth/register')return ok({IdUsuario:'20'},201);
    if(path==='/auth/login')return ok({profile:{IdUsuario:'20',Rol:'Cliente',CorreoElectronico:body.email},accessToken:`fake.${Buffer.from(JSON.stringify({exp:Math.floor(Date.now()/1000)+60})).toString('base64url')}.fake`,cartMerge:null},200,{'Set-Cookie':'sc_refresh=fake'});
    if(path==='/users/me')return expired?Response.json({success:false,error:{code:'INVALID_ACCESS_TOKEN'}},{status:401}):ok({profile:{IdUsuario:'20',Rol:'Cliente'}});
    if(path.startsWith('/catalog/products?'))return ok({products:[]});
    if(path==='/catalog/categories')return ok({category:{IdCategoria:1}},201);
    if(path==='/catalog/products')return ok({product:{IdProducto:'2'}},201);
    if(path==='/catalog/variants')return ok({variant:{IdVariante:'3'}},201);
    if(path==='/inventory/movements'){stock=body.quantity;return ok({movement:{IdMovimiento:'4'}},201);}
    if(path==='/catalog/products/2'&&method==='PATCH')return ok({});
    if(path==='/shipping-methods')return ok({shippingMethods:[{IdMetodoEnvio:1,Codigo:'RETIRO_TIENDA',Costo:'0.0000'}]});
    if(path.startsWith('/inventory?'))return ok({inventory:[{IdVariante:'3',CantidadFisica:stock,CantidadReservada:reserved,Disponible:stock-reserved}]});
    if(path==='/catalog/images'){imageActive=true;return ok({image:{IdImagen:'5'}},201);}
    if(path==='/catalog/images/5'){imageActive=false;return ok({image:{IdImagen:'5'}});}
    if(path==='/catalog/products/2')return ok({variants:[{IdVariante:'3',Disponible:bad?0:stock}],images:imageActive?[{IdImagen:'5',RutaImagen:'test/functional/fixtures/product.svg',TextoAlternativo:c.batch,EsPrincipal:true}]:[]});
    if(path==='/carts/current'){
      const cart=headers.Cookie?.match(/sc_fixture=(\d+)/)?.[1]??String(++cartCounter+100);
      return ok({cart:{IdCarrito:cart,Estado:'ACTIVO',RevisionCarrito:'2026-11-09T00:00:00.0000000'},items:[]},200,{'Set-Cookie':`sc_fixture=${cart}`});
    }
    if(path==='/carts/current/items')return ok({},method==='POST'?200:200);
    if(path==='/checkouts'){
      checkouts++;keys.push(headers['Idempotency-Key']!);
      if(kind==='concurrency'&&checkouts===2&&!bad)return Response.json({success:false,error:{code:'SQL_62710'}},{status:409});
      reserved++;return ok({checkout:{IdCheckout:'6',IdPedido:'7'}},201);
    }
    if(path==='/checkouts/6')return ok({checkout:{EstaVigente:false},inventoryReservations:[{Estado:'ACTIVA'}]});
    if(path==='/orders/payments'){stock=0;reserved=0;return ok({payment:{Estado:'APROBADO'}});}
    if(path==='/orders/7/state')return ok({});
    if(path==='/orders/7')return ok({order:{IdPedido:'7',IdCheckout:'6'},items:[{IdDetallePedido:'8',IdPedido:'7',IdVariante:'3',IdCategoria:1}]});
    if(path==='/returns')return ok({return:{IdDevolucion:'9'}},201);
    if(path==='/returns/9/state')return ok({});
    if(path==='/returns/9/complete'){stock=1;refunds.push({IdReembolso:'10',Estado:'PENDIENTE',Monto:'112.0000'});keys.push(headers['Idempotency-Key']!);return ok({});}
    if(path==='/returns/9/refunds'){
      keys.push(headers['Idempotency-Key']!);
      if(body.action==='RECHAZAR')refunds[0]!.Estado='RECHAZADO';
      else refunds.push({IdReembolso:'11',Estado:'APROBADO',Monto:bad?'1.0000':'112.0000'});
      return ok({refund:refunds.at(-1)});
    }
    if(path==='/orders/7/returns')return ok({refunds});
    assert.fail('Solicitud simulada no prevista: '+method+' '+path);
  };
  try{
    if(kind==='images')await imageScenario(c);
    if(kind==='refunds'){
      await refundScenario(c);assert.equal(keys[1],keys[2]);assert.notEqual(keys[2],keys[3]);
    }
    if(kind==='concurrency'){await raceScenario(c);assert.equal(checkouts,2);assert.notEqual(keys[0],keys[1]);}
    const waits:number[]=[];let firstWaitCalls=0;
    const fakeWait:typeof waitUntil=async deadline=>{if(!waits.length)firstWaitCalls=calls.length;waits.push(deadline);expired=true;reserved=0;};
    if(kind==='expiry')await expiryScenario(c,fakeWait);
    if(kind==='jwt'){await jwtScenario(c,fakeWait);assert.equal(calls.filter(p=>p==='POST /auth/login').length,1);assert.ok(!calls.some(p=>p.includes('/refresh')));}
    if(kind==='expirations'){
      await expirationsScenario(c,fakeWait);
      assert.equal(waits.length,2);assert.ok(waits[1]!>waits[0]!);
      assert.ok(waits[1]!-Date.now()<=902000); // No acumula otra espera de 15 minutos.
      assert.equal(calls.filter(p=>p==='POST /auth/login').length,1);
      assert.ok(calls.slice(firstWaitCalls).every(p=>p.startsWith('GET ')));
    }
    if(kind==='expiry')assert.ok(waits[0]!-Date.now()<=902000);
  }finally{globalThis.fetch=original;c.clear();}
}
for(const kind of ['images','refunds','concurrency','expiry','jwt','expirations'] as const)test(`nuevo ${kind}: orquestación HTTP simulada sin conexiones`,()=>simulated(kind));
for(const kind of ['refunds','concurrency','expiry'] as const)test(`nuevo ${kind}: una invariante incorrecta sigue fallando`,()=>assert.rejects(simulated(kind,true)));
test('permisos: script verifica identidad y permisos efectivos sin DML ni impersonación',async()=>{
  const source=await readFile(new URL('./functional/audit-permissions.sql',import.meta.url),'utf8');
  const code=source.replace(/\/\*[\s\S]*?\*\//g,'');
  assert.match(code,/ORIGINAL_LOGIN\(\)/);assert.match(code,/HAS_PERMS_BY_NAME/);
  assert.doesNotMatch(code,/THROW 65001|COALESCE\(HAS_PERMS_BY_NAME/);
  assert.match(code,/NO_VERIFICABLE/);assert.match(code,/SIN_PERMISO_EFECTIVO/);
  assert.match(code,/PERMISO_PRESENTE/);assert.match(code,/NO_VISIBLE_O_NO_EXISTENTE/);
  assert.match(code,/PARCIAL/);
  const migration=await readFile(new URL('../../database/migrations/010_DevolucionesAuditoria.sql',import.meta.url),'utf8');
  const definition=migration.match(/CREATE TABLE dbo\.EventosAuditoria\s*\(([\s\S]*?)CONSTRAINT PK_EventosAuditoria/)![1]!;
  const columns=[...definition.matchAll(/^\s+(\w+) (bigint|varchar|nvarchar|uniqueidentifier|datetime2)\b/gm)].map(m=>m[1]!);
  assert.equal(columns.length,9);
  for(const column of columns)assert.ok(code.includes(`(N'${column}')`),`Falta consultar columna conocida: ${column}`);
  assert.doesNotMatch(code,/\b(UPDATE|DELETE|INSERT|ALTER|GRANT|DENY|EXECUTE)\s+(dbo\.|AS|ON)/i);
});

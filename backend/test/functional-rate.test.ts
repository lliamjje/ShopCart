import {test,mock} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {AuthBudget,authPolicy,retryAfterSeconds} from './functional/rate-policy.js';
import {Client} from './functional/client.js';
import {Owned} from './functional/safety.js';

test('política funcional coincide con el middleware y las tres rutas compartidas',async()=>{
  const limiter=await readFile(new URL('../src/middleware/rateLimit.ts',import.meta.url),'utf8');
  assert.equal(Number(limiter.match(/b\.count>(\d+)/)?.[1]),authPolicy.limit);
  assert.equal(Number(limiter.match(/until:now\+(\d+)\*60000/)?.[1])*60,authPolicy.windowSeconds);
  const routes=await readFile(new URL('../src/routes/auth.routes.ts',import.meta.url),'utf8');
  assert.deepEqual([...routes.matchAll(/post\('\/(\w+)',authRateLimit/g)].map(m=>m[1]),['register','login','refresh']);
  assert.ok(!/post\('\/logout',authRateLimit/.test(routes));
});
test('plan actual consume quince intentos de autenticación, incluidos negativos',()=>{
  const budget=new AuthBudget();
  const steps=['login','register','login','register','login','register','login','register','login','login','register','login','login','refresh','refresh'];
  for(const route of steps)assert.ok(budget.reserve('POST','/auth/'+route,true));
  assert.equal(budget.used,15);
  budget.reserve('GET','/auth/csrf',false);budget.reserve('POST','/auth/logout',true);
  budget.reserve('POST','/auth/login',false); // CSRF falla antes del limiter.
  assert.equal(budget.used,15);
});
test('Retry-After valida segundos y fecha HTTP; rechaza valores ambiguos o fuera de ventana',()=>{
  const now=Date.UTC(2026,10,9,12,0,0);
  assert.equal(retryAfterSeconds('30',now),30);
  assert.equal(retryAfterSeconds(new Date(now+30000).toUTCString(),now),30);
  for(const value of [null,'','-1','0','1.5','901','Infinity','mañana','999999999999999999999'])assert.equal(retryAfterSeconds(value,now),undefined);
  assert.equal(retryAfterSeconds(new Date(now-1000).toUTCString(),now),undefined);
});
test('clientes del mismo contexto comparten presupuesto y bloquean el intento 21 antes de enviarlo',async()=>{
  let requests=0;const budget=new AuthBudget();
  const clients=[new Client(new Owned(),()=>{},false,budget),new Client(new Owned(),()=>{},false,budget)];
  mock.method(globalThis,'fetch',async()=>{requests++;return new Response(JSON.stringify({success:true,data:{}}),{status:200});});
  try{
    for(const client of clients)client.csrf='FAKE_CSRF';
    for(let i=0;i<20;i++)await clients[i%2]!.raw('POST','/auth/login');
    await assert.rejects(()=>clients[0]!.raw('POST','/auth/login'),/Presupuesto local/);
    assert.equal(requests,20);assert.equal(budget.used,20);
  }finally{mock.restoreAll();}
});
test('un 429 informa Retry-After y se detiene sin esperar ni repetir la escritura',async()=>{
  let requests=0;const client=new Client(new Owned(),()=>{});client.csrf='FAKE_CSRF';
  mock.method(globalThis,'fetch',async()=>{requests++;return new Response(JSON.stringify({success:false,error:{code:'RATE_LIMITED'}}),{status:429,headers:{'Retry-After':'30'}});});
  try{
    await assert.rejects(()=>client.call('POST','/auth/login'),error=>error instanceof Error&&error.message.includes('RATE_LIMITED')&&error.message.includes('30 segundos')&&error.message.includes('Sin reintento'));
    assert.equal(requests,1);
  }finally{mock.restoreAll();}
});
test('el lanzador no impone esperas y mantiene modos offline separados',async()=>{
  const script=await readFile(new URL('./functional/run.ps1',import.meta.url),'utf8');
  assert.doesNotMatch(script,/Start-Sleep|15 minutos y 2 segundos/);
  assert.ok(script.includes('if (-not ($List -or $CheckTransport))'));
  assert.ok(script.includes('if (-not $readOnly)'));
});

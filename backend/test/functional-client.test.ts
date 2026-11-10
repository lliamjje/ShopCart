import {test,mock} from 'node:test';
import assert from 'node:assert/strict';
import {Client,SafeFailure,type Logger} from './functional/client.js';
import {Owned} from './functional/safety.js';
import {Context} from './functional/context.js';
test('cliente funcional: omite secretos de los registros y envía una sola solicitud',async()=>{
  const logs:unknown[]=[];let calls=0;
  mock.method(globalThis,'fetch',async()=>{calls++;return new Response(JSON.stringify({success:true,data:{accessToken:'FAKE_SECRET_TOKEN'}}),{status:200,headers:{'set-cookie':'sc_refresh=FAKE_COOKIE_SECRET; HttpOnly'}});});
  try{
    const client=new Client(new Owned(),row=>logs.push(row));client.csrf='FAKE_CSRF_SECRET';
    await client.raw('POST','/auth/login',{email:'fake@example.invalid',password:'FAKE_PASSWORD_SECRET'});
    assert.equal(calls,1);
    assert.doesNotMatch(JSON.stringify(logs),/FAKE_|password|Cookie|Authorization/);
  }finally{mock.restoreAll();}
});
test('cliente funcional: transporte incierto nunca reintenta ni expone la excepción',async()=>{
  let calls=0;const logs:Parameters<Logger>[0][]=[];
  mock.method(globalThis,'fetch',async()=>{calls++;throw new Error('FAKE_PASSWORD_SECRET');});
  try{
    const client=new Client(new Owned(),row=>logs.push(row));
    await assert.rejects(()=>client.raw('POST','/auth/login',{}),error=>error instanceof SafeFailure&&!error.message.includes('FAKE_'));
    assert.equal(calls,1);assert.equal(logs.at(-1)?.status,'INCIERTO');
  }finally{mock.restoreAll();}
});
test('cliente funcional: recurso ajeno se rechaza antes del transporte HTTP',async()=>{
  let calls=0;mock.method(globalThis,'fetch',async()=>{calls++;return new Response('{}');});
  try{
    const client=new Client(new Owned(),()=>{});
    await assert.rejects(()=>client.raw('POST','/inventory/movements',{variantId:'1'}));
    assert.equal(calls,0);
  }finally{mock.restoreAll();}
});
test('cliente funcional: un 2xx inesperado conserva el ID observado sin autorizar modificaciones',async()=>{
  const owned=new Owned('ACTUAL');const logs:Parameters<Logger>[0][]=[];
  mock.method(globalThis,'fetch',async()=>new Response(JSON.stringify({success:true,data:{category:{IdCategoria:77}}}),{status:201}));
  try{
    const client=new Client(owned,row=>logs.push(row),true);
    await assert.rejects(()=>client.call('POST','/catalog/categories',{name:'QA ACTUAL'},403));
    assert.equal(logs.at(-1)?.observedIds?.['category.IdCategoria'],'77');
    assert.throws(()=>owned.require('category','77'));
  }finally{mock.restoreAll();}
});
test('contexto funcional: líneas de otro pedido o variante no obtienen pertenencia',async()=>{
  const c=new Context(()=>{}),client=c.client(true);
  c.owned.add('order','20');c.owned.add('checkout','30');c.owned.add('variant','40');c.owned.add('category','50');
  let line={IdDetallePedido:'90',IdPedido:'1',IdVariante:'40',IdCategoria:50};
  mock.method(client,'call',async()=>({order:{IdPedido:'20',IdCheckout:'30'},items:[line]}));
  try{
    await assert.rejects(()=>c.order(client,'20'));assert.throws(()=>c.owned.require('line','90'));
    line={...line,IdPedido:'20',IdVariante:'1'};
    await assert.rejects(()=>c.order(client,'20'));assert.throws(()=>c.owned.require('line','90'));
    line={...line,IdVariante:'40'};
    await c.order(client,'20');assert.doesNotThrow(()=>c.owned.require('line','90'));
  }finally{mock.restoreAll();}
});
test('contexto funcional: no habilita un carrito con líneas ajenas al lote',async()=>{
  const c=new Context(()=>{}),client=c.client(true);
  mock.method(client,'call',async()=>({cart:{IdCarrito:'20',Estado:'ACTIVO'},items:[{IdVariante:'1'}]}));
  try{
    await assert.rejects(()=>c.cart(client));assert.throws(()=>c.owned.require('cart','20'));
  }finally{mock.restoreAll();}
});
test('cliente funcional: diagnóstico incluye método, ruta y código sin consultas ni secretos',async()=>{
  const logs:unknown[]=[];
  mock.method(globalThis,'fetch',async()=>new Response(JSON.stringify({success:false,error:{code:'SQL_62103',message:'FAKE_BODY_SECRET'}}),{status:403}));
  try{
    const client=new Client(new Owned(),row=>logs.push(row));client.token='FAKE_JWT_SECRET';
    for(const path of ['/reports/operations?token=FAKE_QUERY_SECRET&module=REEMBOLSOS','/orders/FAKE_PATH_SECRET?password=FAKE_QUERY_SECRET']){
      await assert.rejects(()=>client.call('GET',path),error=>{
        if(!(error instanceof SafeFailure))return false;
        assert.match(error.message,/GET \/(?:reports\/operations|orders\/:parametro)/);
        assert.match(error.message,/esperado 200, recibido 403/);assert.match(error.message,/SQL_62103/);
        assert.doesNotMatch(error.message,/FAKE_|\?/);return true;
      });
    }
    assert.doesNotMatch(JSON.stringify(logs),/FAKE_|password|token=/);
  }finally{mock.restoreAll();}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {Owned,guard} from './functional/safety.js';
import {parseConfig} from './functional/config.js';

test('funcional: configuración exige confirmación y permite smoke sin credenciales',()=>{
  assert.throws(()=>parseConfig('{}'));
  assert.deepEqual(parseConfig(JSON.stringify({email:'',password:'',confirm:'DATOS_FICTICIOS_EN_SHOPCART',modules:['smoke']})).modules,['smoke']);
  assert.throws(()=>parseConfig(JSON.stringify({email:'',password:'',confirm:'DATOS_FICTICIOS_EN_SHOPCART',modules:['all']})));
  assert.deepEqual(parseConfig('\uFEFF'+JSON.stringify({email:'',password:'',confirm:'DATOS_FICTICIOS_EN_SHOPCART',modules:['smoke']})+'\n').modules,['smoke']);
});
test('funcional: solo se modifican recursos registrados en el lote',()=>{
  const owned=new Owned();owned.add('product','100');owned.add('category','90');owned.add('variant','101');
  assert.doesNotThrow(()=>guard('PATCH','/catalog/products/100',{categoryId:90},owned,false));
  assert.throws(()=>guard('PATCH','/catalog/products/1',{categoryId:90},owned,false));
  assert.throws(()=>guard('POST','/inventory/movements',{variantId:'1'},owned,false));
  assert.doesNotThrow(()=>guard('POST','/inventory/movements',{variantId:'101'},owned,false));
  assert.throws(()=>guard('POST','/catalog/products',{categoryId:1},owned,false));
});
test('funcional: bloquea borrados, expiración global y cambios al administrador',()=>{
  const owned=new Owned();
  assert.throws(()=>guard('DELETE','/catalog/products/1',{},owned,false));
  assert.throws(()=>guard('POST','/checkouts/expire',{},owned,false));
  assert.throws(()=>guard('PATCH','/users/me',{firstName:'x'},owned,false));
  assert.throws(()=>guard('GET','/carts/current',{},owned,false));
  assert.throws(()=>guard('POST','/auth/logout',{all:true},owned,false));
  assert.doesNotThrow(()=>guard('POST','/auth/logout',{all:false},owned,false));
  assert.throws(()=>guard('POST','/auth/register',{email:'real@example.com'},owned,true));
  assert.throws(()=>guard('POST','/auth/register',{email:'qa@example.invalid'},owned,false));
});
test('funcional: referencias a pedidos y líneas ajenas no se envían',()=>{
  const owned=new Owned();owned.add('order','20');owned.add('line','21');
  assert.doesNotThrow(()=>guard('POST','/returns',{orderId:'20',items:[{orderItemId:'21',quantity:1}]},owned,true));
  assert.throws(()=>guard('POST','/returns',{orderId:'20',items:[{orderItemId:'1',quantity:1}]},owned,true));
  assert.throws(()=>guard('POST','/orders/payments',{orderId:'1',action:'APROBAR'},owned,true));
  assert.throws(()=>guard('POST','/orders/payments',{orderId:'20',action:'APROBAR'},owned,false));
});
test('funcional: escribe solo rutas existentes y no accede a configuración SQL',async()=>{
  const manifest=JSON.parse(await readFile(new URL('../api-contract.json',import.meta.url),'utf8'));
  for(const path of ['/api/v1/auth/register','/api/v1/catalog/variants','/api/v1/inventory/movements','/api/v1/orders/payments','/api/v1/returns'])
    assert.ok(manifest.endpoints.some((e:{path:string})=>e.path===path));
  const client=await readFile(new URL('./functional/client.ts',import.meta.url),'utf8');
  assert.ok(!/from ['"](?:mssql|dotenv)|config\/database|\.query\(/.test(client));
  assert.equal((client.match(/await fetch\(/g)??[]).length,1);
});

test('funcional: métodos incompatibles no pasan la lista de escrituras',()=>{
  const owned=new Owned();owned.add('category','10');owned.add('product','11');
  assert.throws(()=>guard('POST','/catalog/products/11',{categoryId:10},owned,false));
  assert.throws(()=>guard('PATCH','/inventory/movements',{},owned,true));
  assert.throws(()=>guard('PUT','/users/me',{},owned,true));
  assert.doesNotThrow(()=>guard('PATCH','/catalog/products/11',{categoryId:10},owned,false));
});
test('funcional: correos, categorías, SKU y cupones de otro lote se bloquean',()=>{
  const owned=new Owned('ACTUAL');owned.add('category','10');owned.add('product','11');owned.add('variant','12');
  assert.throws(()=>guard('POST','/auth/register',{email:'qa-otro-a@example.invalid'},owned,true));
  assert.doesNotThrow(()=>guard('POST','/auth/register',{email:'qa-actual-a@example.invalid'},owned,true));
  assert.throws(()=>guard('POST','/catalog/categories',{name:'QA OTRO'},owned,false));
  assert.throws(()=>guard('POST','/catalog/variants',{productId:'11',sku:'QA-OTRO-M'},owned,false));
  assert.throws(()=>guard('POST','/coupons',{code:'QA-OTRO'},owned,false));
  assert.throws(()=>guard('POST','/inventory/movements',{variantId:'12',reason:'OTRO'},owned,true));
});

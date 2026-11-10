import {test,mock} from 'node:test';
import assert from 'node:assert/strict';
import {Context} from './functional/context.js';
import {reports} from './functional/modules/reports.js';
import type {Row} from './support/values.js';

test('reportes funcionales: Operador consulta operación y recibe 403 en módulos financieros; Administrador recibe 200',async()=>{
  const c=new Context(()=>{}),operator=c.client(true);c.users.operator=operator;c.ids.category='50';
  const requests:{role:string;module:string;expected:number}[]=[];
  mock.method(c,'findPage',async()=>({Clave:'50',UnidadesNetas:'1',VentasNetasProductos:'100.8000'}));
  mock.method(operator,'call',async(method:string,path:string,_body:Row={},expected=200)=>{
    assert.equal(method,'GET');const module=new URL('http://localhost'+path).searchParams.get('module')!;
    requests.push({role:'Operador',module,expected});
    if(['REEMBOLSOS','CUPONES'].includes(module)){assert.equal(expected,403);return {code:'SQL_62103'};}
    assert.equal(expected,200);return {rows:[]};
  });
  mock.method(c.admin,'call',async(method:string,path:string,_body:Row={},expected=200)=>{
    assert.equal(method,'GET');
    if(path.startsWith('/reports/operations?')){
      const module=new URL('http://localhost'+path).searchParams.get('module')!;
      assert.ok(['REEMBOLSOS','CUPONES'].includes(module));assert.equal(expected,200);
      requests.push({role:'Administrador',module,expected});return {rows:[]};
    }
    if(path.startsWith('/reports/sales?'))return {sales:[],shipping:{}};
    if(expected===400)return {code:'INVALID_DATE_RANGE'};
    return {cashFlow:{},averageTicket:{},ordersByState:[],returnsByState:[]};
  });
  try{
    await reports[0]!.run(c);
    assert.equal(requests.length,8);
    for(const module of ['INVENTARIO','MOVIMIENTOS','RESERVAS','DEVOLUCIONES'])
      assert.ok(requests.some(r=>r.role==='Operador'&&r.module===module&&r.expected===200));
    for(const module of ['REEMBOLSOS','CUPONES']){
      assert.ok(requests.some(r=>r.role==='Operador'&&r.module===module&&r.expected===403));
      assert.ok(requests.some(r=>r.role==='Administrador'&&r.module===module&&r.expected===200));
    }
  }finally{mock.restoreAll();c.clear();}
});

test('reportes funcionales: conservar una venta neta incorrecta sigue causando fallo',async()=>{
  const c=new Context(()=>{});
  mock.method(c,'findPage',async()=>({UnidadesNetas:'1',VentasNetasProductos:'201.6000'}));
  try{await assert.rejects(()=>reports[0]!.run(c),/reporte neto propio no cuadra/);}
  finally{mock.restoreAll();c.clear();}
});

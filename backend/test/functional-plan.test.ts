import {test} from 'node:test';
import assert from 'node:assert/strict';
import {all,selectScenarios} from './functional/plan.js';
import {executeScenarios} from './functional/execution.js';
import type {Context,Scenario} from './functional/context.js';

test('plan funcional: 33 escenarios implementados y seis pendientes explícitos',()=>{
  assert.equal(all.filter(s=>!s.pending).length,33);
  assert.equal(all.filter(s=>s.pending).length,6);
  assert.equal(new Set(all.map(s=>s.module+':'+s.name)).size,all.length);
  assert.equal(selectScenarios(['all']).length,39);
});
test('plan funcional: selección incluye dependencias previas sin duplicarlas',()=>{
  assert.deepEqual(selectScenarios(['smoke']).map(s=>s.module),['smoke','smoke']);
  const selected=selectScenarios(['sessions']);
  assert.equal(selected.length,33);
  assert.equal(selected[0]?.module,'smoke');assert.equal(selected.at(-1)?.module,'sessions');
  assert.throws(()=>selectScenarios(['all','auth']));
  assert.throws(()=>selectScenarios(['desconocido']));
});
test('plan funcional: detecta dependencias inexistentes, ciclos y orden inválido',()=>{
  const noop=async()=>{};
  assert.throws(()=>selectScenarios(['a'],[{module:'a',name:'a',requires:['b'],run:noop}]));
  assert.throws(()=>selectScenarios(['a'],[{module:'a',name:'a',requires:['b'],run:noop},{module:'b',name:'b',requires:['a'],run:noop}]));
  assert.throws(()=>selectScenarios(['a'],[{module:'a',name:'a',run:noop},{module:'b',name:'b',run:noop},{module:'a',name:'repetido',run:noop}]));
});
test('ejecución funcional: un fallo omite toda operación posterior y no ejecuta pendientes',async()=>{
  let actions=0;
  const plan:Scenario[]=[
    {module:'a',name:'primera',run:async()=>{actions++;}},
    {module:'a',name:'fallo',run:async()=>{actions++;throw Error('INFORMACION_NO_PUBLICABLE');}},
    {module:'b',name:'no ejecutar',run:async()=>{actions++;}},
    {module:'pending',name:'pendiente',pending:'Requiere permiso adicional',run:async()=>{actions++;}}
  ];
  const executed=await executeScenarios(plan,{} as Context,()=>{});
  assert.equal(actions,2);assert.equal(executed.stopped,true);
  assert.deepEqual(executed.results.map(r=>r.result),['APROBADA','FALLIDA','OMITIDA','OMITIDA']);
  assert.ok(!JSON.stringify(executed.results).includes('INFORMACION_NO_PUBLICABLE'));
});

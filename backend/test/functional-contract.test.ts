import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';

test('contrato funcional: todas las llamadas con rutas explícitas coinciden con el manifiesto real',async()=>{
  const manifest=JSON.parse(await readFile(new URL('../api-contract.json',import.meta.url),'utf8')) as {
    endpoints:{method:string;path:string;fields?:({field:string}|string)[]}[]
  };
  const files=(await readdir(new URL('./functional/modules/',import.meta.url))).filter(f=>f.endsWith('.ts')).map(f=>'modules/'+f);
  files.push('context.ts','client.ts');let checked=0;
  for(const file of files){
    const source=await readFile(new URL('./functional/'+file,import.meta.url),'utf8');
    // Verificación de las rutas literales y templates usados actualmente. Los
    // payloads variables se contrastan además en la revisión de los contratos.
    for(const match of source.matchAll(/\.(?:call|raw)\(\s*(['"])(GET|POST|PATCH|DELETE)\1\s*,\s*(['"`])([\s\S]*?)\3/g)){
      const method=match[2]!,route=match[4]!.replace(/\$\{[^}]+\}/g,'123').split('?')[0]!;
      if(!route.startsWith('/'))continue; // helper que recibe la ruta del llamador
      if(route==='/qa-functional-missing'){assert.equal(method,'GET');continue;}
      const endpoint=manifest.endpoints.find(e=>e.method===method&&new RegExp('^'+e.path.replace(/:[A-Za-z]+/g,'[^/]+')+'$').test('/api/v1'+route));
      assert.ok(endpoint,`${file}: ruta o método fuera del contrato: ${method} ${route}`);
      checked++;
    }
  }
  assert.ok(checked>=60,'La auditoría no encontró todas las llamadas previstas.');
});

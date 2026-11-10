import { parseConfig, ConfigFailure } from './config.js';
import { Context } from './context.js';
import {executeScenarios,type Result} from './execution.js';
import { all, selectScenarios } from './plan.js';
import {authPolicy} from './rate-policy.js';
import {SafeFailure} from './client.js';
import {preflight} from './preflight.js';
let startupStage='CARGA';
let scenariosStarted=false;

async function main():Promise<void>{
  if(process.argv.includes('--auth-policy')){console.log(JSON.stringify(authPolicy));return;}
  if(process.argv.includes('--list')) {
    console.table(all.map(s=>({module:s.module,scenario:s.name,status:s.pending?'PENDIENTE':'IMPLEMENTADA',reason:s.pending??''})));
    return;
  }
  // Las credenciales solo entran por stdin anónimo del lanzador, nunca argv/env/archivos.
  startupStage='STDIN';
  console.log('[EJECUTOR] Leyendo entrada por stdin. Aun no se han iniciado solicitudes HTTP.');
  const chunks:Buffer[]=[];let size=0;
  for await(const chunk of process.stdin){const b=Buffer.from(chunk);size+=b.length;if(size>16384)throw Error('Entrada excesiva.');chunks.push(b);}
  const buffer=Buffer.concat(chunks);
  let config:ReturnType<typeof parseConfig>;
  try{startupStage='CONFIGURACION';config=parseConfig(buffer.toString('utf8'));}
  finally{buffer.fill(0);for(const chunk of chunks)chunk.fill(0);}
  if(process.argv.includes('--check-transport')) {
    if(config.password!=='prueba-sin-secretos-\u00f1"\\')throw new ConfigFailure('INPUT_CREDENTIALS');
    config.password='';config.email='';
    console.log('Canal PowerShell -> Node UTF-8: OK. Modo offline, sin solicitudes HTTP.');
    return;
  }
  startupStage='PLAN';
  if(process.argv.includes('--preflight')){
    if(config.modules.length!==1||config.modules[0]!=='preflight')throw new ConfigFailure('INPUT_SHAPE');
    const c=new Context(op=>console.log(JSON.stringify({operation:op})));
    startupStage='PREFLIGHT';
    try{
      await preflight(c,config.email,config.password);
      console.log('[PREFLIGHT] APROBADO: CSRF, login HTTP 200 y perfil HTTP 200; Administrador ID 3. Fin sin escenarios.');
    }catch(error){
      console.log(JSON.stringify({preflightFailure:{stage:startupStage,message:error instanceof SafeFailure?error.message:'Fallo interno; detalle omitido por seguridad.'}}));
      process.exitCode=1;
    }finally{config.password='';config.email='';c.clear();}
    return;
  }
  const scenarios=selectScenarios(config.modules);
  const selected=new Set(scenarios.map(s=>s.module));
  let active='preparación';
  const operations:Record<string,unknown>[]=[];
  let sent=0;
  const c=new Context(op=>{const row={scenario:active,...op};if(op.status==='ENVIADA')sent++;else if(op.method==='GET')sent++;operations.push(row);console.log(JSON.stringify({operation:row}));});
  const results:Result[]=[];
  let stopped=false;
  try{
    startupStage='PREPARACION_HTTP';
    console.log('[EJECUTOR] Entrada y plan validados; comienza preparación HTTP.');
    console.log(JSON.stringify({batch:c.batch,modules:[...selected],notice:'Datos propios; sin reintentos, SQL directo, borrados ni modificación del catálogo anterior.'}));
    await c.guest.init();
    if(selected.has('auth')){
      startupStage='PREFLIGHT';
      await preflight(c,config.email,config.password);
      console.log('[PREFLIGHT] APROBADO; se reutiliza la sesión administrativa en los escenarios.');
    }
    config.password='';config.email='';
    const executed=await executeScenarios(scenarios,c,scenario=>{
      startupStage='ESCENARIOS';scenariosStarted=true;
      active=scenario.module+': '+scenario.name;console.log(JSON.stringify({start:active}));
    });
    results.push(...executed.results);stopped=executed.stopped;
    if(stopped)process.exitCode=1;
  }catch(error){
    stopped=true;process.exitCode=1;
    results.push({module:scenariosStarted?'ejecución':'preparación',scenario:active,result:'FALLIDA',reason:error instanceof SafeFailure?error.message:`Error en etapa ${startupStage}; no se reintenta.`});
    for(const s of scenarios)if(!results.some(r=>r.module===s.module&&r.scenario===s.name))results.push({module:s.module,scenario:s.name,result:'OMITIDA',reason:scenariosStarted?'Ejecución interrumpida.':'Preparación fallida.'});
  }finally{
    config.password='';config.email='';c.clear();
    console.table(results);
    console.log(JSON.stringify({authAttempts:c.authBudget.used,authLimit:authPolicy.limit,authWindowSeconds:authPolicy.windowSeconds}));
    console.log(JSON.stringify({batch:c.batch,resources:c.owned.snapshot(),fixtures:['m','l','org'].filter(label=>c.ids[label]).map(label=>({id:c.ids[label],sku:c.values[label]?.sku,productId:c.values[label]?.productId})),summary:{passed:results.filter(r=>r.result==='APROBADA').length,failed:results.filter(r=>r.result==='FALLIDA').length,skipped:results.filter(r=>r.result==='OMITIDA').length,requests:sent},notice:stopped?'No se ejecutó limpieza tras el fallo. Conservar el lote para diagnóstico; una escritura incierta puede estar aplicada.':'El historial ficticio se conserva. No se borran ni desactivan automáticamente recursos.'}));
  }
}
main().catch(error=>{
  console.log(JSON.stringify({executorFailure:{stage:startupStage,code:error instanceof ConfigFailure?error.code:'EXECUTOR_FAILURE',message:error instanceof ConfigFailure?error.message:'El ejecutor falló en esta etapa. No se muestran excepciones ni datos de entrada.',scenariosStarted}}));
  process.exitCode=1;
});

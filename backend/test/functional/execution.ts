import {SafeFailure} from './client.js';
import type {Context,Scenario} from './context.js';
export interface Result {module:string;scenario:string;result:'APROBADA'|'FALLIDA'|'OMITIDA';reason:string}
export async function executeScenarios(scenarios:Scenario[],context:Context,start:(s:Scenario)=>void):Promise<{results:Result[];stopped:boolean}>{
  const results:Result[]=[];let stopped=false;
  for(const scenario of scenarios){
    if(scenario.pending||stopped){
      results.push({module:scenario.module,scenario:scenario.name,result:'OMITIDA',reason:scenario.pending??'Detención preventiva tras un fallo anterior.'});
      continue;
    }
    start(scenario);
    try{
      await scenario.run(context);
      results.push({module:scenario.module,scenario:scenario.name,result:'APROBADA',reason:''});
    }catch(error){
      stopped=true;
      results.push({module:scenario.module,scenario:scenario.name,result:'FALLIDA',reason:error instanceof SafeFailure?error.message:'Aserción o contrato inesperado. Revisar la última operación confirmada y los IDs del lote.'});
    }
  }
  return {results,stopped};
}

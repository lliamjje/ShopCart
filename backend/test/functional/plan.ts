import type {Scenario} from './context.js';
import { smoke } from './modules/smoke.js';
import { auth,sessions } from './modules/auth.js';
import { users } from './modules/users.js';
import { catalog,publication } from './modules/catalog.js';
import { inventory } from './modules/inventory.js';
import { carts } from './modules/carts.js';
import { coupons } from './modules/coupons.js';
import { checkout } from './modules/checkout.js';
import { payments } from './modules/payments.js';
import { orders } from './modules/orders.js';
import { returns } from './modules/returns.js';
import { reports } from './modules/reports.js';
import { edges } from './modules/edges.js';

const pending:Scenario[]=[
 ['Expiración efectiva tras 15 minutos','Preparada: -NewScenario expiry; espera real explícita de 16 minutos, sin expire global.'],
 ['Concurrencia y carga','Carrera preparada: -NewScenario concurrency; bloqueada mientras SQL 62710 no se traduzca a 409. Carga masiva fuera de alcance.'],
 ['Denegación SQL de UPDATE/DELETE de auditoría','Verificación de lectura separada: audit-permissions.sql con conexión de servicio; no se ejecuta desde API.'],
 ['JWT expirado por tiempo real','Preparada: -NewScenario jwt; espera hasta exp del JWT original sin alterar relojes.'],
 ['Reembolso rechazado y nuevo intento','Preparada: -NewScenario refunds con pedido, pago y devolución nuevos propios.'],
 ['Imágenes de producto','Metadatos preparados: -NewScenario images. Upload/servir archivos no existe en el contrato.']
].map(([name,reason])=>({module:'pending',name:name!,pending:reason!,run:async()=>{}}));
export const all=[...smoke,...auth,...users,...catalog,...inventory,...publication,...carts,...coupons,...checkout,...payments,...orders,...returns,...reports,...edges,...sessions,...pending];


export function selectScenarios(names:string[], plan:Scenario[]=all):Scenario[]{
  const modules=new Set(plan.map(s=>s.module));
  if(!names.length||(names.includes('all')&&names.length!==1)||names.some(n=>n!=='all'&&!modules.has(n)))throw Error('Módulos inválidos.');
  const completed=new Set<string>();
  let previous='';
  for(const s of plan){
    if(previous&&previous!==s.module)completed.add(previous);
    if(previous!==s.module&&completed.has(s.module))throw Error('Módulo intercalado.');
    for(const dependency of s.requires??[])if(!modules.has(dependency)||!completed.has(dependency))throw Error('Dependencia inexistente, circular o fuera de orden.');
    previous=s.module;
  }
  const selected=new Set(names.includes('all')?[...modules]:names);
  let changed=true;while(changed){changed=false;for(const s of plan)if(selected.has(s.module))for(const d of s.requires??[])if(!selected.has(d)){selected.add(d);changed=true;}}
  return plan.filter(s=>selected.has(s.module));
}

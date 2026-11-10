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
 ['Expiración efectiva tras 15 minutos','Prueba prolongada pendiente; no se cambia el reloj ni se ejecuta expire global sobre datos existentes.'],
 ['Concurrencia y carga','Requiere autorización de carga separada; la suite funcional es secuencial.'],
 ['Denegación SQL de UPDATE/DELETE de auditoría','Requiere revisar permisos con una cuenta específica; no se usa SQL directo.'],
 ['JWT expirado por tiempo real','Cubierto localmente; prueba HTTP prolongada pendiente sin fabricar ni firmar tokens.'],
 ['Reembolso rechazado y nuevo intento','Pendiente de un fixture independiente para no mezclar operaciones monetarias ya resueltas.'],
 ['Imágenes de producto','Pendiente de un archivo local autorizado; no se crean rutas ficticias a archivos inexistentes.']
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

import type { Scenario } from '../context.js';
import { check } from '../client.js';
import { object,rows,money } from '../../support/values.js';
export const reports:Scenario[]=[
 {module:'reports',name:'Venta neta propia excluye cancelación y descuenta devolución',requires:['returns'],run:async c=>{
   const sale=await c.findPage(c.admin,`/reports/sales?${c.interval()}&dimension=CATEGORIA`,'sales',row=>row.Clave===c.ids.category);
   check(sale&&BigInt(String(sale.UnidadesNetas))===1n&&money(sale.VentasNetasProductos)===1008000n,'El reporte neto propio no cuadra.');
   for(const dimension of ['DIA','SEMANA','MES','PRODUCTO','TOP']){
     const report=await c.admin.call('GET',`/reports/sales?${c.interval()}&dimension=${dimension}`);rows(report.sales);object(report.shipping);
   }
   const finance=await c.admin.call('GET',`/reports/finance?${c.interval()}`);object(finance.cashFlow);object(finance.averageTicket);rows(finance.ordersByState);rows(finance.returnsByState);
   const operator=c.user('operator');
   for(const module of ['INVENTARIO','MOVIMIENTOS','RESERVAS','DEVOLUCIONES'])
     rows((await operator.call('GET',`/reports/operations?${c.interval()}&module=${module}`)).rows);
   for(const module of ['REEMBOLSOS','CUPONES']){
     const path=`/reports/operations?${c.interval()}&module=${module}`;
     const denied=await operator.call('GET',path,{},403);
     check(denied.code==='SQL_62103','El reporte financiero debe rechazar al Operador por autorización SQL.');
     rows((await c.admin.call('GET',path)).rows);
   }
   await c.admin.call('GET',`/reports/finance?from=${encodeURIComponent(c.to)}&to=${encodeURIComponent(c.from)}`,{},400);
 }},
 {module:'reports',name:'Auditoría de entidad propia, filtros y paginación',run:async c=>{
   const event=await c.findPage(c.admin,`/audit?${c.interval()}&entity=Categorias&userId=${c.admin.userId}`,'events',r=>String(r.IdEntidad)===c.ids.category&&r.Accion==='GUARDAR');
   check(event&&typeof event.DatosNuevos==='string','Falta auditoría de la categoría propia.');
   const payload=object(JSON.parse(event.DatosNuevos));check(payload.Nombre==='QA '+c.batch,'Evento no corresponde al lote.');
   check(!/HashContrasena|TokenInvitadoHash|password/.test(event.DatosNuevos),'Auditoría expone secretos.');
 }}
];

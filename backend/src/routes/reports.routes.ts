import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const reportsOperations = [
{method:"get",path:"/sales",procedure:"SP_Reportes_Ventas",access:"admin",sets:["sales","shipping"],single:["shipping"],bindings:{Desde:bind("from",s.instant),Hasta:bind("to",s.instant),Dimension:bind("dimension",z.enum(['DIA','SEMANA','MES','PRODUCTO','CATEGORIA','TOP']).default('DIA')),Pagina:bind("page",s.page),TamanoPagina:bind("pageSize",s.pageSize),Top:bind("top",z.coerce.number().int().min(1).max(100).default(10))}},
{method:"get",path:"/finance",procedure:"SP_Reportes_Finanzas",access:"admin",sets:["cashFlow","ordersByState","averageTicket","returnsByState"],single:["cashFlow","averageTicket"],bindings:{Desde:bind("from",s.instant),Hasta:bind("to",s.instant)}},
{method:"get",path:"/operations",procedure:"SP_Reportes_Operacion",access:"operator",sets:["rows"],single:[],bindings:{Desde:bind("from",s.instant),Hasta:bind("to",s.instant),Modulo:bind("module",z.enum(['INVENTARIO','MOVIMIENTOS','RESERVAS','DEVOLUCIONES','REEMBOLSOS','CUPONES'])),Pagina:bind("page",s.page),TamanoPagina:bind("pageSize",s.pageSize)}}
] satisfies readonly Operation[];
export const reportsRoutes=operationRouter(reportsOperations);

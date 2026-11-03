import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const auditOperations = [
{method:"get",path:"/",procedure:"SP_Auditoria_Consultar",access:"admin",sets:["events"],single:[],bindings:{Desde:bind("from",s.instant),Hasta:bind("to",s.instant),IdUsuario:bind("userId",s.id.optional()),Entidad:bind("entity",s.text(100).optional()),IdCorrelacion:bind("correlationId",s.uuid.optional()),Modulo:bind("module",z.enum(['CATALOGO','SEGURIDAD','INVENTARIO','VENTAS','DEVOLUCIONES','CUPONES']).optional()),Pagina:bind("page",s.page),TamanoPagina:bind("pageSize",s.pageSize)}}
] satisfies readonly Operation[];
export const auditRoutes=operationRouter(auditOperations);

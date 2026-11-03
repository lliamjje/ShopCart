import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const inventoryOperations = [
{method:"get",path:"/",procedure:"SP_Inventario_Consultar",access:"operator",sets:["inventory"],single:[],bindings:{IdVariante:bind("variantId",s.id.optional()),Umbral:bind("threshold",z.coerce.number().int().min(0).max(2147483647).optional()),Pagina:bind("page",s.page),TamanoPagina:bind("pageSize",s.pageSize)}},
{method:"post",path:"/movements",procedure:"SP_Inventario_RegistrarMovimiento",access:"operator",sets:["movement"],single:["movement"],status:201,bindings:{IdVariante:bind("variantId",s.id),Tipo:bind("type",z.enum(['ENTRADA','SALIDA','AJUSTE_POSITIVO','AJUSTE_NEGATIVO'])),Cantidad:bind("quantity",s.quantity),Motivo:bind("reason",s.text(500)),IdOperacion:bind("operationId",s.id)}},
{method:"get",path:"/movements",procedure:"SP_Inventario_ListarMovimientos",access:"operator",sets:["movements"],single:[],bindings:{Desde:bind("from",s.instant),Hasta:bind("to",s.instant),IdVariante:bind("variantId",s.id.optional()),Pagina:bind("page",s.page),TamanoPagina:bind("pageSize",s.pageSize)}}
] satisfies readonly Operation[];
export const inventoryRoutes=operationRouter(inventoryOperations);

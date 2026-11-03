import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const returnsOperations = [
{method:"post",path:"/",procedure:"SP_Devoluciones_Solicitar",access:"optional",sets:["return"],single:["return"],status:201,idempotency:{"parameter":"IdOperacion","scope":"RETURN","uuid":true},bindings:{IdPedido:bind("orderId",s.id),Lineas:bind("items",s.returnLines),Motivo:bind("reason",s.text(500))}},
{method:"post",path:"/:id/items",procedure:"SP_Devoluciones_Solicitar",access:"optional",sets:["return"],single:["return"],idempotency:{"parameter":"IdOperacion","scope":"RETURN","uuid":true},bindings:{IdDevolucion:bind("id",s.id),IdPedido:bind("orderId",s.id),Lineas:bind("items",s.returnLines),Motivo:bind("reason",s.text(500))}},
{method:"get",path:"/",procedure:"SP_Devoluciones_Listar",access:"operator",sets:["returns"],single:[],bindings:{Estado:bind("state",s.returnState.optional()),Pagina:bind("page",s.page),TamanoPagina:bind("pageSize",s.pageSize)}},
{method:"patch",path:"/:id/state",procedure:"SP_Devoluciones_CambiarEstado",access:"operator",sets:[],single:[],bindings:{IdDevolucion:bind("id",s.id),EstadoNuevo:bind("state",z.enum(['APROBADA','RECHAZADA','RECIBIDA'])),Observacion:bind("note",s.optionalText(1000))}},
{method:"post",path:"/:id/cancel",procedure:"SP_Devoluciones_CambiarEstado",access:"optional",sets:[],single:[],bindings:{IdDevolucion:bind("id",s.id),EstadoNuevo:constant("CANCELADA"),Observacion:bind("note",s.optionalText(1000))}},
{method:"post",path:"/:id/complete",procedure:"SP_Devoluciones_Completar",access:"operator",sets:["return","refunds"],single:["return"],idempotency:{"parameter":"ClaveReembolso","scope":"REFUND","reference":"Referencia"},bindings:{IdDevolucion:bind("id",s.id)}},
{method:"post",path:"/:id/refunds",procedure:"SP_Devoluciones_ProcesarReembolso",access:"operator",sets:["refund"],single:["refund"],idempotency:{"parameter":"ClaveOperacion","scope":"REFUND","reference":"Referencia"},bindings:{IdDevolucion:bind("id",s.id),Accion:bind("action",z.enum(['CREAR','APROBAR','RECHAZAR']))}}
] satisfies readonly Operation[];
export const returnsRoutes=operationRouter(returnsOperations);

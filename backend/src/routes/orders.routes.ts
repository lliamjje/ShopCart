import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const ordersOperations = [
{method:"post",path:"/payments",procedure:"SP_Pedidos_ProcesarPago",access:"optional",sets:["payment"],single:["payment"],paymentAmount:true,idempotency:{"parameter":"ClaveOperacion","scope":"PAY","reference":"Referencia"},bindings:{IdPedido:bind("orderId",s.id),Accion:bind("action",z.enum(['CREAR','APROBAR','RECHAZAR']))}},
{method:"get",path:"/",procedure:"SP_Pedidos_Listar",access:"user",sets:["orders"],single:[],bindings:{Administrativo:constant(false),Estado:bind("state",s.orderState.optional()),Desde:bind("from",s.instant.optional()),Hasta:bind("to",s.instant.optional()),Pagina:bind("page",s.page),TamanoPagina:bind("pageSize",s.pageSize)}},
{method:"get",path:"/admin",procedure:"SP_Pedidos_Listar",access:"operator",sets:["orders"],single:[],bindings:{Administrativo:constant(true),IdUsuario:bind("userId",s.id.optional()),Estado:bind("state",s.orderState.optional()),Desde:bind("from",s.instant.optional()),Hasta:bind("to",s.instant.optional()),Pagina:bind("page",s.page),TamanoPagina:bind("pageSize",s.pageSize)}},
{method:"get",path:"/number/:number",procedure:"SP_Pedidos_Consultar",access:"optional",sets:["order","items","payments","history"],single:["order"],bindings:{NumeroPedido:bind("number",s.text(30))}},
{method:"get",path:"/:id",procedure:"SP_Pedidos_Consultar",access:"optional",sets:["order","items","payments","history"],single:["order"],bindings:{IdPedido:bind("id",s.id)}},
{method:"get",path:"/:id/returns",procedure:"SP_Devoluciones_Consultar",access:"optional",sets:["returns","items","refunds","cancellationRefunds"],single:[],bindings:{IdPedido:bind("id",s.id)}},
{method:"post",path:"/:id/cancel",procedure:"SP_Pedidos_Cancelar",access:"optional",sets:["order","refunds"],single:["order"],idempotency:{"parameter":"ClaveReembolso","scope":"CANCEL","reference":"Referencia"},bindings:{IdPedido:bind("id",s.id)}},
{method:"patch",path:"/:id/state",procedure:"SP_Pedidos_CambiarEstado",access:"operator",sets:[],single:[],bindings:{IdPedido:bind("id",s.id),EstadoNuevo:bind("state",z.enum(['EN_PREPARACION','ENVIADO','ENTREGADO'])),Observacion:bind("note",s.optionalText(500))}}
] satisfies readonly Operation[];
export const ordersRoutes=operationRouter(ordersOperations);

import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const couponsOperations = [
{method:"post",path:"/validate",procedure:"SP_Cupones_ValidarCarrito",access:"optional",sets:["quote"],single:["quote"],bindings:{IdCarrito:bind("cartId",s.id),Codigo:bind("code",s.text(50))}},
{method:"post",path:"/",procedure:"SP_Cupones_Guardar",access:"admin",sets:["coupon"],single:["coupon"],status:201,bindings:{IdCupon:constant(null),Codigo:bind("code",s.text(50)),Tipo:bind("type",z.enum(['PORCENTAJE','MONTO_FIJO'])),Valor:bind("value",s.money.refine(v=>Number(v)>0)),Minimo:bind("minimum",s.money),Inicio:bind("startsAt",s.instant),Fin:bind("endsAt",s.instant),IdCategoria:bind("categoryId",s.intId.nullish()),LimiteTotal:bind("globalLimit",s.quantity.nullish()),LimiteUsuario:bind("userLimit",s.quantity.nullish()),Activo:bind("active",s.bool.default(true)),Descripcion:bind("description",s.optionalText(250))}},
{method:"patch",path:"/:id",procedure:"SP_Cupones_Guardar",access:"admin",sets:["coupon"],single:["coupon"],status:200,bindings:{IdCupon:bind("id",s.id),Codigo:bind("code",s.text(50)),Tipo:bind("type",z.enum(['PORCENTAJE','MONTO_FIJO'])),Valor:bind("value",s.money.refine(v=>Number(v)>0)),Minimo:bind("minimum",s.money),Inicio:bind("startsAt",s.instant),Fin:bind("endsAt",s.instant),IdCategoria:bind("categoryId",s.intId.nullish()),LimiteTotal:bind("globalLimit",s.quantity.nullish()),LimiteUsuario:bind("userLimit",s.quantity.nullish()),Activo:bind("active",s.bool.default(true)),Descripcion:bind("description",s.optionalText(250))}},
{method:"patch",path:"/:id/state",procedure:"SP_Cupones_CambiarEstado",access:"admin",sets:[],single:[],bindings:{IdCupon:bind("id",s.id),Activo:bind("active",s.bool)}},
{method:"get",path:"/:id/uses",procedure:"SP_Cupones_ConsultarUsos",access:"admin",sets:["uses"],single:[],bindings:{IdCupon:bind("id",s.id),Pagina:bind("page",s.page),TamanoPagina:bind("pageSize",s.pageSize)}}
] satisfies readonly Operation[];
export const couponsRoutes=operationRouter(couponsOperations);

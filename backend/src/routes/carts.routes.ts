import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const cartsOperations = [
{method:"get",path:"/current",procedure:"SP_Carritos_Consultar",access:"optional",sets:["cart","items","totals"],single:["cart","totals"],currentCart:true,csrf:true,bindings:{}},
{method:"post",path:"/current/items",procedure:"SP_Carritos_Modificar",access:"optional",sets:[],single:[],currentCart:true,bindings:{Accion:constant("AGREGAR"),IdVariante:bind("variantId",s.id),Cantidad:bind("quantity",s.quantity)}},
{method:"patch",path:"/current/items/:id",procedure:"SP_Carritos_Modificar",access:"optional",sets:[],single:[],currentCart:true,bindings:{Accion:constant("FIJAR"),IdVariante:bind("id",s.id),Cantidad:bind("quantity",s.quantity)}},
{method:"delete",path:"/current/items/:id",procedure:"SP_Carritos_Modificar",access:"optional",sets:[],single:[],currentCart:true,bindings:{Accion:constant("QUITAR"),IdVariante:bind("id",s.id)}},
{method:"delete",path:"/current/items",procedure:"SP_Carritos_Modificar",access:"optional",sets:[],single:[],currentCart:true,bindings:{Accion:constant("VACIAR")}},
{method:"get",path:"/:id",procedure:"SP_Carritos_Consultar",access:"optional",sets:["cart","items","totals"],single:["cart","totals"],bindings:{IdCarrito:bind("id",s.id)}}
] satisfies readonly Operation[];
export const cartsRoutes=operationRouter(cartsOperations);

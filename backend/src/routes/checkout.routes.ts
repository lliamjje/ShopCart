import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const checkoutOperations = [
{method:"post",path:"/",procedure:"SP_Checkout_Iniciar",access:"optional",sets:["checkout"],single:["checkout"],status:201,idempotency:{"parameter":"ClaveIdempotencia","scope":"CHECKOUT"},bindings:{IdCarrito:bind("cartId",s.id),RevisionCarrito:bind("cartRevision",s.revision),IdMetodoEnvio:bind("shippingMethodId",s.intId),NombreDestinatario:bind("recipientName",s.text(150)),Telefono:bind("phone",s.text(25)),Departamento:bind("department",s.text(100)),Ciudad:bind("city",s.text(100)),Direccion1:bind("address1",s.text(250)),Direccion2:bind("address2",s.optionalText(250)),CodigoPostal:bind("postalCode",s.optionalText(15)),IdDireccion:bind("addressId",s.id.nullish()),CodigoCupon:bind("couponCode",s.optionalText(50))}},
{method:"post",path:"/expire",procedure:"SP_Checkout_Expirar",access:"operator",sets:["expiration"],single:["expiration"],bindings:{Limite:bind("limit",z.number().int().min(1).max(1000).default(100))}},
{method:"get",path:"/:id",procedure:"SP_Checkout_Consultar",access:"optional",sets:["checkout","items","inventoryReservations","couponReservations","order"],single:["checkout","order"],bindings:{IdCheckout:bind("id",s.id)}},
{method:"post",path:"/:id/cancel",procedure:"SP_Checkout_Cancelar",access:"optional",sets:[],single:[],bindings:{IdCheckout:bind("id",s.id)}}
] satisfies readonly Operation[];
export const checkoutRoutes=operationRouter(checkoutOperations);

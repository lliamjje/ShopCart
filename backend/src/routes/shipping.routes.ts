import { z } from 'zod';
import { operationRouter,bind,constant } from './operationRouter.js';
import * as s from '../schemas/common.js';
import type { Operation } from '../types/operation.js';

export const shippingOperations = [
{method:"get",path:"/",procedure:"SP_Checkout_ListarMetodosEnvio",access:"public",sets:["shippingMethods"],single:[],bindings:{}}
] satisfies readonly Operation[];
export const shippingRoutes=operationRouter(shippingOperations);

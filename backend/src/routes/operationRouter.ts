import { Router } from 'express';
import type { Operation,Binding } from '../types/operation.js';
import { optionalAuthentication,authenticate } from '../middleware/authenticate.js';
import { authorize } from '../middleware/authorize.js';
import { requireCsrf } from '../middleware/csrf.js';
import { operationController } from '../controllers/operation.controller.js';
import { procedures } from '../repositories/storedProcedures.js';
import type { z } from 'zod';
export const bind=(field:string,schema:z.ZodType):Binding=>({field,schema});
export const constant=(value:string|number|boolean|null):Binding=>({constant:value});
export function operationRouter(operations:readonly Operation[]):Router{
 const router=Router(),seen=new Set<string>();
 for(const op of operations){
 const key=op.method+':'+op.path;if(seen.has(key))throw new Error('Ruta duplicada: '+key);seen.add(key);
 const names=new Set<string>(procedures[op.procedure].params.map(p=>p.name));
 for(const name of Object.keys(op.bindings)){
 if(!names.has(name)||['IdActor','IdSesion','TokenInvitado'].includes(name))throw new Error('Mapeo SQL no autorizado: '+name);
 }
 const middleware=[];
 if(op.access!=='public')middleware.push(optionalAuthentication);
 if(['user','operator','admin'].includes(op.access))middleware.push(authenticate);
 if(op.access==='operator')middleware.push(authorize('Operador','Administrador'));
 if(op.access==='admin')middleware.push(authorize('Administrador'));
 if(op.csrf)middleware.push(requireCsrf);
 router[op.method](op.path,...middleware,operationController(op));
 }return router;
}

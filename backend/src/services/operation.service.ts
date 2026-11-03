import type { Request,Response } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { operationKey,uuid } from '../schemas/common.js';
import { mappedCall,executeProcedure,type Row } from '../repositories/procedure.repository.js';
import { procedures,type SqlInput } from '../repositories/storedProcedures.js';
import type { Operation } from '../types/operation.js';
import { guestHash } from '../utils/cookies.js';
import { idempotencyHash } from '../utils/tokens.js';
import { AppError } from '../utils/errors.js';
function sqlValue(value:unknown):SqlInput|undefined {
 if(value===undefined||value===null||typeof value==='string'||typeof value==='number'||typeof value==='boolean'||value instanceof Date||Buffer.isBuffer(value))return value;
 throw new AppError(500,'SQL_MAPPING_ERROR','Valor no convertible al contrato SQL.');
}
function withoutSecrets(value:unknown):unknown {
 if(Array.isArray(value))return value.map(withoutSecrets);
 if(value&&typeof value==='object'){
 const result:Row={};
 for(const [k,v] of Object.entries(value))if(!/hash|token|claveidempotencia/i.test(k))result[k]=withoutSecrets(v);
 return result;
 }return value;
}
export async function runOperation(op:Operation,req:Request,res:Response):Promise<unknown>{
 const shape:Record<string,z.ZodType>={};
 for(const b of Object.values(op.bindings))if(b.field&&b.schema)shape[b.field]=b.schema;
 const body=op.method==='get'?{}:req.body??{};
 const input=validate(z.object(shape).strict(),{...req.query,...body,...req.params});
 const values:Record<string,SqlInput|undefined>={};
 for(const [sqlName,b] of Object.entries(op.bindings))values[sqlName]='constant' in b?b.constant:sqlValue(input[b.field??sqlName]);
 const defs=procedures[op.procedure].params;
 const has=(n:string)=>defs.some(p=>p.name===n);
 const guest=!req.identity&&(has('TokenInvitado')||op.currentCart)?guestHash(req,res,op.currentCart===true):undefined;
 if(has('IdActor'))values.IdActor=req.identity?.id??null;
 if(has('IdSesion'))values.IdSesion=req.identity?.sessionId??null;
 if(has('TokenInvitado'))values.TokenInvitado=req.identity?null:guest??null;
 if(op.currentCart){
 const result=await executeProcedure('SP_Carritos_ObtenerActivo',{
 IdActor:req.identity?.id??null,IdSesion:req.identity?.sessionId??null,
 TokenInvitado:req.identity?null:guest??null});
 const id=result.recordsets[0]?.[0]?.IdCarrito;
 if(typeof id!=='string')throw new AppError(503,'SQL_CONTRACT_ERROR','Contrato de carrito inesperado.');
 values.IdCarrito=id;
 }
 if(op.idempotency){
 const raw=req.get('Idempotency-Key');
 const key=validate(op.idempotency.uuid?uuid:operationKey,raw);
 values[op.idempotency.parameter]=op.idempotency.uuid?key:idempotencyHash(key,op.idempotency.scope);
 if(op.idempotency.reference)values[op.idempotency.reference]=op.idempotency.scope+'-'+idempotencyHash(key,op.idempotency.scope).toString('hex');
 }
 if(op.paymentAmount){
 const data=await executeProcedure('SP_Pedidos_Consultar',{IdPedido:typeof values.IdPedido==='string'?values.IdPedido:null,
 IdActor:req.identity?.id??null,IdSesion:req.identity?.sessionId??null,
 TokenInvitado:req.identity?null:guestHash(req)??null});
 const total=data.recordsets[0]?.[0]?.Total;
 if(typeof total!=='string')throw new AppError(503,'SQL_CONTRACT_ERROR','No se obtuvo el total confirmado del pedido.');
 values.Monto=total;
 }
 if(values.Desde instanceof Date&&values.Hasta instanceof Date&&values.Desde>=values.Hasta)
 throw new AppError(400,'INVALID_DATE_RANGE','La fecha inicial debe ser anterior a la final.');
 const result=await mappedCall(op.procedure,values);
 const mapped:Row={};
 for(let i=0;i<op.sets.length;i++){
 const key=op.sets[i];if(!key)continue;
 const rows=result.recordsets[i]??[];
 mapped[key]=op.single?.includes(key)?rows[0]??null:rows;
 }
 if(Object.keys(result.output).length) mapped.output=result.output;
 return withoutSecrets(mapped);
}

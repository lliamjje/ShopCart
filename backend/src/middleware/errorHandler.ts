import type { ErrorRequestHandler } from 'express';
import { AppError } from '../utils/errors.js';
export const errorHandler:ErrorRequestHandler=(error:unknown,_req,res,_next)=>{
 const e=error as {type?:string;status?:number};
 const safe=error instanceof AppError?error:e.type==='entity.too.large'?new AppError(413,'PAYLOAD_TOO_LARGE','Solicitud demasiado grande.'):
 e.type==='entity.parse.failed'?new AppError(400,'INVALID_JSON','JSON inválido.'):
 new AppError(500,'INTERNAL_ERROR','Error interno del servidor.');
 // Nunca registrar el objeto SQL/HTTP completo: puede contener credenciales.
 res.status(safe.status).json({success:false,error:{code:safe.code,message:safe.message}});
};

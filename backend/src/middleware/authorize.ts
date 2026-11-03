import type { RequestHandler } from 'express';
import type { Role } from '../types/auth.js';
import { AppError } from '../utils/errors.js';
export function authorize(...allowed:Role[]):RequestHandler{return(req,_res,next)=>{
 if(!req.identity){next(new AppError(401,'AUTHENTICATION_REQUIRED','Autenticación requerida.'));return;}
 if(!allowed.includes(req.identity.role)){next(new AppError(403,'FORBIDDEN','Operación no autorizada.'));return;}next();
};}

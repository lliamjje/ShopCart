import type { RequestHandler } from 'express';
import { readAccess } from '../utils/tokens.js';
import { executeProcedure } from '../repositories/procedure.repository.js';
import { roles,type Identity } from '../types/auth.js';
import { AppError } from '../utils/errors.js';
export const optionalAuthentication:RequestHandler=async(req,_res,next)=>{
 try{
 const header=req.get('Authorization');if(!header){next();return;}
 if(!header.startsWith('Bearer ')||header.length>4096)throw new AppError(401,'INVALID_ACCESS_TOKEN','Credencial inválida.');
 const claims=readAccess(header.slice(7));
 const r=await executeProcedure('SP_Seguridad_ConsultarPerfil',{IdActor:claims.id,IdSesion:claims.sessionId});
 const profile=r.recordsets[0]?.[0];
 if(!profile||typeof profile.Rol!=='string'||!roles.includes(profile.Rol as Identity['role']))
 throw new AppError(401,'INVALID_SESSION','Sesión inválida.');
 req.identity={...claims,role:profile.Rol as Identity['role']};next();
 }catch(e){next(e);}
};
export const authenticate:RequestHandler=(req,_res,next)=>{
 if(!req.identity){next(new AppError(401,'AUTHENTICATION_REQUIRED','Autenticación requerida.'));return;}next();
};

import type { RequestHandler } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { text,bool } from '../schemas/common.js';
import * as auth from '../services/auth.service.js';
import { cookie,cookieNames,setRefresh,clearRefresh,guestHash,baseCookie } from '../utils/cookies.js';
import { executeProcedure } from '../repositories/procedure.repository.js';
import { env } from '../config/env.js';
import { AppError } from '../utils/errors.js';
const credentials=z.object({email:z.email().max(254).transform(v=>v.trim().toLowerCase()),password:z.string().min(1).max(128)}).strict();
export const register:RequestHandler=async(req,res)=>{
 const input=validate(credentials.extend({password:z.string().min(12).max(128),firstName:text(100),lastName:text(100)}),req.body);
 const data=await auth.register(input);res.status(201).json({success:true,data});
};
export const login:RequestHandler=async(req,res)=>{
 const input=validate(credentials,req.body);
 const result=await auth.login(input.email,input.password,req.ip,req.get('User-Agent'));
 setRefresh(res,result.refresh,result.expires);
 let merge:unknown=null;
 const guest=guestHash(req);
 if(guest){try{merge=await auth.mergeGuest(result.identity,guest);}
 catch(e){if(e instanceof AppError)merge={status:'pending',code:e.code};else throw e;}}
 res.json({success:true,data:{accessToken:result.accessToken,expiresIn:env.ACCESS_TOKEN_SECONDS,profile:result.profile,cartMerge:merge}});
};
export const refresh:RequestHandler=async(req,res)=>{
 validate(z.object({}).strict(),req.body??{});
 const raw=cookie(req,cookieNames.refresh);
 if(!raw)throw new AppError(401,'REFRESH_REQUIRED','Renovación requerida.');
 try{const result=await auth.renew(raw);setRefresh(res,result.refresh,result.expires);
 res.json({success:true,data:{accessToken:result.accessToken,profile:result.profile}});
 }catch(e){if(e instanceof AppError&&e.status===401)clearRefresh(res);throw e;}
};
export const logout:RequestHandler=async(req,res)=>{
 const data=validate(z.object({all:bool.default(false)}).strict(),req.body??{});
 const identity=req.identity;if(!identity)throw new AppError(401,'AUTHENTICATION_REQUIRED','Autenticación requerida.');
 await executeProcedure('SP_Seguridad_RevocarSesiones',{IdActor:identity.id,IdSesion:identity.sessionId,Todas:data.all});
 clearRefresh(res);res.json({success:true,data:{}});
};
export const merge:RequestHandler=async(req,res)=>{
 validate(z.object({}).strict(),req.body??{});
 const identity=req.identity,guest=guestHash(req);
 if(!identity||!guest)throw new AppError(401,'GUEST_CREDENTIAL_REQUIRED','Falta la identidad o el carrito invitado.');
 const data=await auth.mergeGuest(identity,guest);res.json({success:true,data});
};

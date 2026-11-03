import type { RequestHandler } from 'express';
import { cookie,cookieNames,baseCookie } from '../utils/cookies.js';
import { equal,secretToken } from '../utils/tokens.js';
import { env } from '../config/env.js';
import { AppError } from '../utils/errors.js';
export const issueCsrf:RequestHandler=(_req,res)=>{
 const token=secretToken();res.cookie(cookieNames.csrf,token,{...baseCookie,httpOnly:false,maxAge:86400000});
 res.set('Cache-Control','no-store').json({success:true,data:{csrfToken:token}});
};
export const requireCsrf:RequestHandler=(req,_res,next)=>{
 const origin=req.get('Origin');
 if(origin&&origin!==env.CORS_ORIGIN){next(new AppError(403,'CSRF_REJECTED','Origen no autorizado.'));return;}
 const sent=req.get('X-CSRF-Token'),saved=cookie(req,cookieNames.csrf);
 if(!sent||!saved||!/^[A-Za-z0-9_-]{43}$/.test(sent)||!equal(sent,saved)){
 next(new AppError(403,'CSRF_REJECTED','Falta una prueba CSRF válida.'));return;
 }next();
};
export const csrfForMutations:RequestHandler=(req,res,next)=>{
 if(['GET','HEAD','OPTIONS'].includes(req.method)){next();return;} requireCsrf(req,res,next);
};

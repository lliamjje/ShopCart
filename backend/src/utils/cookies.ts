import type { Request,Response,CookieOptions } from 'express';
import { env } from '../config/env.js';
import { secretToken,tokenHash } from './tokens.js';
import { AppError } from './errors.js';
const prefix=env.NODE_ENV==='production'?'__Host-':'';
export const cookieNames={guest:prefix+'sc_guest',refresh:prefix+'sc_refresh',csrf:prefix+'sc_csrf'};
export const baseCookie:CookieOptions={httpOnly:true,secure:env.NODE_ENV==='production',sameSite:'strict',path:'/'};
export function cookie(req:Request,name:string):string|undefined {
 const values=req.cookies as Record<string,unknown>|undefined;const v=values?.[name];return typeof v==='string'?v:undefined;
}
export function guestHash(req:Request,res?:Response,create=false):Buffer|undefined {
 let token=cookie(req,cookieNames.guest);
 if(token&&!/^[A-Za-z0-9_-]{43}$/.test(token))throw new AppError(401,'INVALID_GUEST_TOKEN','Credencial de invitado inválida.');
 if(!token&&create&&res){token=secretToken();res.cookie(cookieNames.guest,token,{...baseCookie,maxAge:30*86400000});}
 return token?tokenHash(token):undefined;
}
export function setRefresh(res:Response,token:string,expires:Date):void {res.cookie(cookieNames.refresh,token,{...baseCookie,expires});}
export function clearRefresh(res:Response):void {res.clearCookie(cookieNames.refresh,baseCookie);}

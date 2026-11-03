import { randomBytes,createHash,timingSafeEqual } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import type { Identity } from '../types/auth.js';
import { AppError } from './errors.js';
export const secretToken=()=>randomBytes(32).toString('base64url');
export const tokenHash=(token:string)=>createHash('sha256').update(token,'utf8').digest();
export function equal(a:string,b:string):boolean {const x=Buffer.from(a),y=Buffer.from(b);return x.length===y.length&&timingSafeEqual(x,y);}
export function accessToken(user:Identity):string {
 return jwt.sign({sid:user.sessionId},env.JWT_SECRET,{algorithm:'HS256',subject:user.id,issuer:'shopcart',audience:'shopcart-api',expiresIn:env.ACCESS_TOKEN_SECONDS});
}
export function readAccess(token:string):{id:string;sessionId:string} {
 try {
 const p=jwt.verify(token,env.JWT_SECRET,{algorithms:['HS256'],issuer:'shopcart',audience:'shopcart-api'});
 if(typeof p==='string'||typeof p.sub!=='string'||typeof p.sid!=='string'||!/^[1-9]\d{0,18}$/.test(p.sub)||!isUuid(p.sid))throw Error();
 return {id:p.sub,sessionId:p.sid};
 }catch{throw new AppError(401,'INVALID_ACCESS_TOKEN','Credencial inválida o expirada.');}
}
export const isUuid=(s:string)=>/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(s);
export function refreshToken(expires:Date):string {
 return jwt.sign({nonce:secretToken(),exp:Math.floor(expires.getTime()/1000)},env.JWT_SECRET,{algorithm:'HS256',issuer:'shopcart',audience:'shopcart-refresh'});
}
export function readRefresh(token:string):Date {
 try{const p=jwt.verify(token,env.JWT_SECRET,{algorithms:['HS256'],issuer:'shopcart',audience:'shopcart-refresh'});
 if(typeof p==='string'||typeof p.exp!=='number'||typeof p.nonce!=='string')throw Error();
 return new Date(p.exp*1000);
 }catch{throw new AppError(401,'INVALID_REFRESH_TOKEN','Renovación inválida o expirada.');}
}
export function idempotencyHash(key:string,scope:string):Buffer {
 return tokenHash(scope+':'+key);
}

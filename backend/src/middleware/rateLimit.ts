import type { RequestHandler } from 'express';
import { AppError } from '../utils/errors.js';
const buckets=new Map<string,{count:number;until:number}>();
// Una instancia local; no confiar en X-Forwarded-For (trust proxy deshabilitado).
export const authRateLimit:RequestHandler=(req,res,next)=>{
 const now=Date.now();for(const [k,v] of buckets)if(v.until<=now)buckets.delete(k);
 const key=req.ip??'unknown',b=buckets.get(key)??{count:0,until:now+15*60000};
 if(buckets.size>=10000&&!buckets.has(key)){next(new AppError(429,'RATE_LIMITED','Intente más tarde.'));return;}
 b.count++;buckets.set(key,b);
 if(b.count>20){res.set('Retry-After',String(Math.ceil((b.until-now)/1000)));next(new AppError(429,'RATE_LIMITED','Demasiados intentos; intente más tarde.'));return;}
 next();
};

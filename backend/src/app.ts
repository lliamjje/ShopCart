import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import cookieParser from 'cookie-parser';
import { env } from './config/env.js';
import { csrfForMutations } from './middleware/csrf.js';
import { errorHandler } from './middleware/errorHandler.js';
import { routes } from './routes/index.js';
export function createApp(){
 const app=express();app.disable('x-powered-by');app.set('trust proxy',false);
 app.use(helmet());
 app.use(cors({origin:env.CORS_ORIGIN,credentials:true,methods:['GET','POST','PATCH','DELETE','OPTIONS'],
 allowedHeaders:['Content-Type','Authorization','X-CSRF-Token','Idempotency-Key']}));
 app.use(express.json({limit:'128kb',strict:true}));
 app.use(cookieParser());
 app.use((_req,res,next)=>{res.set('Cache-Control','no-store');next();});
 app.use('/api/v1',csrfForMutations,routes);
 app.use((_req,res)=>res.status(404).json({success:false,error:{code:'NOT_FOUND',message:'Ruta inexistente.'}}));
 app.use(errorHandler);return app;
}

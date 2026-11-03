import type { RequestHandler } from 'express';
import type { Operation } from '../types/operation.js';
import { runOperation } from '../services/operation.service.js';
export function operationController(op:Operation):RequestHandler {
 return async(req,res)=>{const data=await runOperation(op,req,res);res.status(op.status??200).json({success:true,data});};
}

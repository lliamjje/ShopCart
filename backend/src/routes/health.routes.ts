import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { databaseStatus,getPool } from '../config/database.js';
export const healthRoutes=Router();
healthRoutes.get('/',async(req,res)=>{
 const q=validate(z.object({database:z.enum(['true','false']).default('false')}).strict(),req.query);
 let database: string=databaseStatus();
 if(q.database==='true'){try{await getPool();database='connected';}catch{database='unavailable';}}
 res.status(database==='unavailable'?503:200).json({success:database!=='unavailable',data:{http:'up',database}});
});

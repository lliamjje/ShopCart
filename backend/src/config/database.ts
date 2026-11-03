import sql from 'mssql';
import { env } from './env.js';
let pool: sql.ConnectionPool | undefined;
let connecting: Promise<sql.ConnectionPool> | undefined;
export async function getPool(): Promise<sql.ConnectionPool> {
 if(pool?.connected) return pool;
 if(connecting) return connecting;
 const candidate=new sql.ConnectionPool({
 server:env.SQL_SERVER,port:env.SQL_PORT,database:env.SQL_DATABASE,user:env.SQL_USER,password:env.SQL_PASSWORD,
 connectionTimeout:env.SQL_CONNECT_TIMEOUT_MS,requestTimeout:env.SQL_REQUEST_TIMEOUT_MS,
 pool:{max:10,min:0,idleTimeoutMillis:30000},
 options:{encrypt:env.SQL_ENCRYPT,trustServerCertificate:env.SQL_TRUST_SERVER_CERTIFICATE,useUTC:true,
 enableArithAbort:true,abortTransactionOnError:true}
 });
 candidate.on('error',()=>{ if(pool===candidate) pool=undefined; void candidate.close().catch(()=>undefined); });
 connecting=candidate.connect().then(p=>{pool=p;return p;}).catch(async (e:unknown)=>{
 await candidate.close().catch(()=>undefined);throw e;
 }).finally(()=>{connecting=undefined;});
 return connecting;
}
export async function closePool():Promise<void> {
 const pending=connecting;
 if(pending) await pending.catch(()=>undefined);
 const current=pool;pool=undefined;if(current) await current.close();
}
export function databaseStatus(): 'connected'|'not_connected' {return pool?.connected?'connected':'not_connected';}

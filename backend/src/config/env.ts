import 'dotenv/config';
import { z } from 'zod';
const flag = z.enum(['true','false']).transform(v => v === 'true');
const schema = z.object({
 NODE_ENV: z.enum(['development','test','production']).default('development'),
 PORT: z.coerce.number().int().min(1).max(65535).default(3000),
 HOST: z.string().default('127.0.0.1'),
 SQL_SERVER:z.string().min(1), SQL_PORT:z.coerce.number().int().min(1).max(65535).default(1433),
 SQL_DATABASE:z.literal('ShopCart'), SQL_USER:z.string().min(1), SQL_PASSWORD:z.string().min(1),
 SQL_ENCRYPT:flag.default(true),SQL_TRUST_SERVER_CERTIFICATE:flag.default(false),
 SQL_CONNECT_TIMEOUT_MS:z.coerce.number().int().min(1000).max(30000).default(5000),
 SQL_REQUEST_TIMEOUT_MS:z.coerce.number().int().min(1000).max(60000).default(15000),
 CORS_ORIGIN:z.url(),JWT_SECRET:z.string().min(32),
 ACCESS_TOKEN_SECONDS:z.coerce.number().int().min(60).max(900).default(600),
 SESSION_DAYS:z.coerce.number().int().min(1).max(30).default(7)
}).superRefine((v,c) => {
 const u = new URL(v.CORS_ORIGIN);
 if (u.origin !== v.CORS_ORIGIN) c.addIssue({code:'custom',message:'CORS_ORIGIN debe ser un origen sin ruta.'});
 if (v.NODE_ENV==='production' && (!v.SQL_ENCRYPT || v.SQL_TRUST_SERVER_CERTIFICATE || u.protocol!=='https:'))
 c.addIssue({code:'custom',message:'Producción requiere HTTPS y certificado SQL verificado.'});
 if(v.SQL_TRUST_SERVER_CERTIFICATE && !['127.0.0.1','localhost','::1'].includes(v.SQL_SERVER))
 c.addIssue({code:'custom',message:'Certificado no verificado permitido solo en loopback.'});
});
const result=schema.safeParse(process.env);
if(!result.success) throw new Error('Configuración inválida: '+[...new Set(result.error.issues.map(i=>i.path.join('.') || 'seguridad'))].join(', '));
export const env=result.data;

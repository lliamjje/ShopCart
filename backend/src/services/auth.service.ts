import argon2 from 'argon2';
import { executeProcedure,type Row } from '../repositories/procedure.repository.js';
import { accessToken,refreshToken,readRefresh,tokenHash,secretToken } from '../utils/tokens.js';
import { env } from '../config/env.js';
import type { Identity } from '../types/auth.js';
import { roles } from '../types/auth.js';
import { AppError } from '../utils/errors.js';
const hashOptions={type:argon2.argon2id,memoryCost:65536,timeCost:3,parallelism:1} as const;
let dummy:Promise<string>|undefined;
export async function register(input:{firstName:string;lastName:string;email:string;password:string}):Promise<Row|undefined>{
 const hash=await argon2.hash(input.password,hashOptions);
 const r=await executeProcedure('SP_Seguridad_RegistrarUsuario',{Nombre:input.firstName,Apellido:input.lastName,Correo:input.email.toLowerCase(),HashContrasena:hash});
 return r.recordsets[0]?.[0];
}
async function profile(id:string,sessionId:string):Promise<{identity:Identity;profile:Row}>{
 const r=await executeProcedure('SP_Seguridad_ConsultarPerfil',{IdActor:id,IdSesion:sessionId});
 const p=r.recordsets[0]?.[0];
 if(!p||typeof p.Rol!=='string'||!roles.includes(p.Rol as Identity['role']))throw new AppError(401,'INVALID_SESSION','Sesión inválida.');
 return {identity:{id,sessionId,role:p.Rol as Identity['role']},profile:p};
}
export async function login(email:string,password:string,ip:string|undefined,agent:string|undefined){
 const result=await executeProcedure('SP_Seguridad_ObtenerAutenticacion',{Correo:email.toLowerCase()});
 const user=result.recordsets[0]?.[0];
 const fallback=await (dummy??=argon2.hash(secretToken(),hashOptions));
 let valid=false;
 try{valid=await argon2.verify(typeof user?.HashContrasena==='string'?user.HashContrasena:fallback,password);}catch{valid=false;}
 if(!valid||!user?.EstaActivo||typeof user.IdUsuario!=='string')throw new AppError(401,'INVALID_CREDENTIALS','Correo o contraseña incorrectos.');
 // Segundos enteros: el JWT refresh y el límite absoluto SQL coinciden.
 const expires=new Date((Math.floor(Date.now()/1000)+env.SESSION_DAYS*86400)*1000);
 const refresh=refreshToken(expires);
 const r=await executeProcedure('SP_Seguridad_CrearSesion',{IdUsuario:user.IdUsuario,HashToken:tokenHash(refresh),FechaExpiracionUTC:expires,DireccionIP:ip?.slice(0,45)??null,Agente:agent?.slice(0,500)??null});
 const sessionId=r.recordsets[0]?.[0]?.IdSesion;
 if(typeof sessionId!=='string')throw new AppError(503,'SQL_CONTRACT_ERROR','Contrato de sesión inesperado.');
 const p=await profile(user.IdUsuario,sessionId);
 return {...p,accessToken:accessToken(p.identity),refresh,expires};
}
export async function renew(raw:string){
 const expires=readRefresh(raw),refresh=refreshToken(expires);
 const r=await executeProcedure('SP_Seguridad_RotarToken',{HashAnterior:tokenHash(raw),HashNuevo:tokenHash(refresh),NuevaExpiracionUTC:expires});
 const row=r.recordsets[0]?.[0];
 if(typeof row?.IdUsuario!=='string'||typeof row.IdSesion!=='string')throw new AppError(503,'SQL_CONTRACT_ERROR','Contrato de renovación inesperado.');
 const p=await profile(row.IdUsuario,row.IdSesion);
 return {...p,accessToken:accessToken(p.identity),refresh,expires};
}
export async function mergeGuest(identity:Identity,hash:Buffer):Promise<Row|undefined>{
 const g=await executeProcedure('SP_Carritos_ObtenerActivo',{IdActor:null,IdSesion:null,TokenInvitado:hash});
 const id=g.recordsets[0]?.[0]?.IdCarrito;
 if(typeof id!=='string')throw new AppError(503,'SQL_CONTRACT_ERROR','Contrato de carrito inesperado.');
 const r=await executeProcedure('SP_Carritos_Fusionar',{IdActor:identity.id,IdSesion:identity.sessionId,IdCarritoInvitado:id,TokenInvitado:hash});
 return r.recordsets[0]?.[0];
}

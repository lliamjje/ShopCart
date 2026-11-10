import { baseUrl, expectedAdminId } from './config.js';
import { guard, type Owned } from './safety.js';
import { object, id, type Row } from '../support/values.js';
import {AuthBudget,retryAfterSeconds} from './rate-policy.js';
export class SafeFailure extends Error {}
export function check(condition: unknown, message: string): asserts condition { if(!condition) throw new SafeFailure(message); }
export interface Reply { status: number; body: Row; retryAfter?:number }
function publicCode(body:Row):string {
  const value=body.error&&typeof body.error==='object'?(body.error as Row).code:undefined;
  return typeof value==='string'&&/^[A-Z0-9_]{1,80}$/.test(value)?value:'SIN_CODIGO';
}
function diagnosticPath(path:string):string {
  const known=new Set('api v1 auth register login refresh logout csrf users me session addresses access catalog categories products variants inventory movements carts current items merge coupons validate uses checkouts expire cancel orders payments number state returns complete refunds reports sales finance operations audit health qa-functional-missing'.split(' '));
  return path.split(/[?#]/)[0]!.split('/').map(part=>!part||known.has(part)||/^[1-9]\d{0,18}$/.test(part)?part:':parametro').join('/');
}
export type Logger = (operation: {method:string;path:string;status:number|string;code:string;references?:Record<string,string>;observedIds?:Record<string,string>;retryAfter?:number})=>void;
export class Client {
  token = ''; userId = ''; email = ''; password = ''; csrf = '';
  private cookies = new Map<string,string>();
  constructor(readonly owned: Owned, readonly log: Logger, readonly testIdentity = false,readonly authBudget=new AuthBudget()) {}
  cookie(name:string): string { return this.cookies.get(name) ?? ''; }
  async raw(method: string, path: string, body: Row = {}, key?:string, options: {csrf?:boolean;cookie?:string;authorization?:string} = {}): Promise<Reply> {
    guard(method,path,body,this.owned,this.testIdentity);
    const logPath=diagnosticPath(path);
    const headers: Record<string,string> = {};
    if(this.cookies.size) headers.Cookie=[...this.cookies].map(([k,v])=>`${k}=${v}`).join('; ');
    if(options.cookie) headers.Cookie=(headers.Cookie?headers.Cookie+'; ':'')+options.cookie;
    if(options.csrf !== false && this.csrf) headers['X-CSRF-Token']=this.csrf;
    if(this.token || options.authorization) headers.Authorization='Bearer '+(options.authorization??this.token);
    if(key) headers['Idempotency-Key']=key;
    if(method!=='GET') headers['Content-Type']='application/json';
    check(this.authBudget.reserve(method,path,!!headers['X-CSRF-Token']),
      'Presupuesto local de autenticación agotado antes del envío. No se pausa con JWT abiertos ni se reintenta.');
    const references:Record<string,string>={};
    for(const field of ['categoryId','productId','variantId','cartId','orderId','addressId','operationId']) {
      const value=body[field];if((typeof value==='string'||typeof value==='number')&&/^[1-9]\d*$/.test(String(value)))references[field]=String(value);
    }
    if(typeof body.sku==='string'&&/^QA-[A-Z0-9-]+$/.test(body.sku))references.sku=body.sku;
    if(typeof body.quantity==='number'&&Number.isSafeInteger(body.quantity))references.quantity=String(body.quantity);
    if(method!=='GET')this.log({method,path:logPath,status:'ENVIADA',code:'',references});
    let response: Response;
    try { response=await fetch(baseUrl+path,{method,headers,...(method==='GET'?{}:{body:JSON.stringify(body)}),redirect:'error',signal:AbortSignal.timeout(30000)}); }
    catch { this.log({method,path:logPath,status:'INCIERTO',code:'TRANSPORTE',references}); throw new SafeFailure(`${method} ${logPath}: sin respuesta (TRANSPORTE); no se reintenta.`); }
    for(const cookie of response.headers.getSetCookie()) {
      const first=cookie.split(';')[0]!, at=first.indexOf('='); this.cookies.set(first.slice(0,at),first.slice(at+1));
    }
    let payload: Row;
    try { payload=object(await response.json()); }
    catch { this.log({method,path:logPath,status:response.status,code:'CONTRATO',references}); throw new SafeFailure(`${method} ${logPath}: HTTP ${response.status}, respuesta no verificable (CONTRATO); la operación puede estar aplicada.`); }
    const code=publicCode(payload);
    // Incluso una respuesta 2xx inesperada puede haber creado un recurso antes
    // de fallar la aserción. Registrar solo IDs, sin otorgarles pertenencia al lote.
    const observedIds:Record<string,string>={};
    if(payload.data&&typeof payload.data==='object'&&!Array.isArray(payload.data)){
      const fields=['IdUsuario','IdCategoria','IdProducto','IdVariante','IdCarrito','IdCupon','IdCheckout','IdPedido','IdDevolucion','IdMovimiento','IdDireccion','IdPago','IdReembolso','IdReembolsoCancelacion'];
      const collect=(row:Row,label:string)=>{for(const field of fields){const value=row[field];if((typeof value==='string'||typeof value==='number')&&/^[1-9]\d*$/.test(String(value)))observedIds[label+field]=String(value);}};
      const data=payload.data as Row;collect(data,'');
      for(const label of ['profile','category','product','variant','cart','coupon','checkout','order','return','movement','address','payment','refund']){
        const value=data[label];if(value&&typeof value==='object'&&!Array.isArray(value))collect(value as Row,label+'.');
      }
      if(Array.isArray(data.refunds))for(const [index,value] of data.refunds.entries())if(value&&typeof value==='object')collect(value as Row,`refunds[${index}].`);
    }
    const retryAfter=response.status===429?retryAfterSeconds(response.headers.get('Retry-After')):undefined;
    this.log({method,path:logPath,status:response.status,code,references,observedIds,...(retryAfter===undefined?{}:{retryAfter})});
    return {status:response.status,body:payload,...(retryAfter===undefined?{}:{retryAfter})};
  }
  async call(method:string,path:string,body:Row={},expected=200,key?:string):Promise<Row> {
    const response=await this.raw(method,path,body,key);
    const limited=response.status===429?` Sin reintento. ${response.retryAfter===undefined?'Sin Retry-After válido; revisar el límite y otros consumidores.':`Retry-After válido: ${response.retryAfter} segundos; esperar antes de una NUEVA ejecución.`}`:'';
    const diagnostic=`${method} ${diagnosticPath(path)}: HTTP esperado ${expected}, recibido ${response.status}; código ${publicCode(response.body)}.${limited}`;
    check(response.status===expected,diagnostic);
    check(response.body.success === (expected<400),diagnostic+' Indicador success inesperado.');
    return expected<400?object(response.body.data):object(response.body.error);
  }
  async init():Promise<void> {
    this.csrf=(await this.call('GET','/auth/csrf')).csrfToken as string;
    check(typeof this.csrf==='string'&&/^[A-Za-z0-9_-]{43}$/.test(this.csrf)&&this.cookie('sc_csrf')===this.csrf,'CSRF/cookie incompatibles.');
  }
  async login(email:string,password:string,role:string):Promise<void> {
    const data=await this.call('POST','/auth/login',{email,password});
    const profile=object(data.profile); check(profile.Rol===role,'Rol inesperado en login.');
    const received=id(profile.IdUsuario);
    check(profile.CorreoElectronico===email,'El login devolvió otra cuenta.');
    if(this.testIdentity){this.owned.require('user',received);check(!this.userId||this.userId===received,'El login cambió de identidad.');}
    else check(received===expectedAdminId,'No corresponde al Administrador aprobado.');
    this.userId=received; this.token=data.accessToken as string;
    check(typeof this.token==='string'&&this.token.split('.').length===3&&!!this.cookie('sc_refresh'),'JWT o cookie refresh ausentes.');
    check(data.cartMerge===null,'No se esperaba fusión al iniciar sesión.');
  }
  clear():void {this.token='';this.password='';this.csrf='';this.email='';this.cookies.clear();}
}

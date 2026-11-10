// Política de authRateLimit en src/middleware/rateLimit.ts. La regresión local
// detecta cambios del umbral/ventana para evitar una configuración divergente.
export const authPolicy={limit:20,windowSeconds:15*60} as const;
export function retryAfterSeconds(value:string|null,now=Date.now()):number|undefined{
  if(!value)return undefined;
  let seconds:number;
  if(/^\d+$/.test(value))seconds=Number(value);
  else if(/^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$/.test(value)){
    const timestamp=Date.parse(value);
    if(!Number.isFinite(timestamp)||new Date(timestamp).toUTCString()!==value)return undefined;
    seconds=Math.ceil((timestamp-now)/1000);
  }
  else return undefined;
  return Number.isSafeInteger(seconds)&&seconds>0&&seconds<=authPolicy.windowSeconds?seconds:undefined;
}
export class AuthBudget{
  used=0;
  reserve(method:string,path:string,hasCsrf:boolean):boolean{
    if(method!=='POST'||!hasCsrf||!/^\/auth\/(register|login|refresh)$/.test(path.split('?')[0]!))return true;
    if(this.used>=authPolicy.limit)return false;
    this.used++;return true;
  }
}

export interface Config { email: string; password: string; confirm: string; modules: string[] }
export const baseUrl = 'http://127.0.0.1:3000/api/v1';
export const expectedAdminId = '3';
export class ConfigFailure extends Error {
  constructor(readonly code:'INPUT_JSON'|'INPUT_SHAPE'|'INPUT_CREDENTIALS'){
    super({INPUT_JSON:'La entrada no contiene JSON válido.',INPUT_SHAPE:'La estructura de entrada o confirmación no es válida.',INPUT_CREDENTIALS:'Correo o longitud de contraseña inválidos.'}[code]);
  }
}
export function parseConfig(raw: string): Config {
  // Some Windows pipe encodings prepend a BOM; remove only outer whitespace.
  let input:unknown;
  try{input=JSON.parse(raw.trim());}catch{throw new ConfigFailure('INPUT_JSON');}
  if (!input || typeof input !== 'object') throw new ConfigFailure('INPUT_SHAPE');
  const c = input as Record<string, unknown>;
  if (c.confirm !== 'DATOS_FICTICIOS_EN_SHOPCART' || typeof c.email !== 'string' ||
      typeof c.password !== 'string' || !Array.isArray(c.modules) ||
      !c.modules.every(m => typeof m === 'string')) throw new ConfigFailure('INPUT_SHAPE');
  const readOnly=c.modules.length===1&&c.modules[0]==='smoke';
  if(!readOnly&&(!c.email.includes('@')||c.password.length<1||c.password.length>128))throw new ConfigFailure('INPUT_CREDENTIALS');
  return { email: c.email.trim().toLowerCase(), password: c.password, confirm: c.confirm, modules: c.modules as string[] };
}

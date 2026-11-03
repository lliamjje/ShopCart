import { AppError } from './errors.js';
const MONEY_LIMIT = 1_000_000_000;
export function decimalInput(value: unknown):number {
 if(typeof value!=='string' || !/^(0|[1-9]\d*)(\.\d{1,4})?$/.test(value))
 throw new AppError(400,'INVALID_DECIMAL','El importe debe ser una cadena decimal no negativa con hasta 4 decimales.');
 const n=Number(value);
 if(!Number.isFinite(n)||n>MONEY_LIMIT) throw new AppError(422,'DECIMAL_RANGE_UNSUPPORTED','Importe fuera del rango preciso admitido por el adaptador.');
 return n;
}
export function decimalOutput(value:unknown,scale:number):string {
 if(typeof value!=='number'||!Number.isFinite(value)||scale<0||scale>12||Math.abs(value)>Math.min(MONEY_LIMIT,1e13/(10**scale)))
 throw new AppError(422,'DECIMAL_RANGE_UNSUPPORTED','El resultado excede el rango decimal preciso del adaptador.');
 return value.toFixed(scale);
}
export function bigintText(value:unknown):string {
 if(typeof value==='bigint')return value.toString();
 if(typeof value==='number' && Number.isSafeInteger(value)) return String(value);
 if(typeof value==='string' && /^-?\d+$/.test(value))return value;
 throw new AppError(500,'INVALID_SQL_BIGINT','El driver devolvió un identificador no representable sin pérdida.');
}

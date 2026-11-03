import { z } from 'zod';
export const id=z.string().regex(/^[1-9]\d{0,18}$/).refine(v=>BigInt(v)<=9223372036854775807n,'ID fuera de bigint');
export const intId=z.coerce.number().int().min(1).max(2147483647);
export const quantity=z.number().int().min(1).max(2147483647);
export const page=z.coerce.number().int().min(1).max(1000000).default(1);
export const pageSize=z.coerce.number().int().min(1).max(100).default(20);
export const text=(max:number)=>z.string().trim().min(1).max(max);
export const optionalText=(max:number)=>z.string().trim().max(max).nullish().transform(v=>v||null);
export const money=z.string().regex(/^(0|[1-9]\d*)(\.\d{1,4})?$/).refine(v=>Number(v)<=1000000000,'Importe fuera del rango preciso del adaptador');
export const bool=z.union([z.boolean(),z.enum(['true','false']).transform(v=>v==='true')]);
export const instant=z.string().datetime({offset:false}).refine(v=>!(/\\.\\d{4}/.test(v)),'Las fechas de filtro admiten hasta milisegundos; la revisión del carrito conserva 7 decimales como texto.').transform(v=>new Date(v));
export const revision=z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?$/).max(33);
export const orderState=z.enum(['PENDIENTE_PAGO','PAGADO','EN_PREPARACION','ENVIADO','ENTREGADO','CANCELADO']);
export const returnState=z.enum(['SOLICITADA','APROBADA','RECHAZADA','RECIBIDA','COMPLETADA','CANCELADA']);
export const operationKey=z.string().min(16).max(128).regex(/^[A-Za-z0-9_-]+$/);
export const uuid=z.uuid();
export const returnLines=z.array(z.object({orderItemId:id,quantity}).strict()).min(1).max(500)
.refine(rows=>new Set(rows.map(r=>r.orderItemId)).size===rows.length,'Líneas repetidas')
.transform(rows=>JSON.stringify(rows.map(r=>({IdDetallePedido:r.orderItemId,Cantidad:r.quantity}))));

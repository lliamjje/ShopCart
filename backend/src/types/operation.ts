import type { z } from 'zod';
import type { ProcedureName,SqlInput } from '../repositories/storedProcedures.js';
export interface Binding {field?:string;schema?:z.ZodType;constant?:SqlInput}
export type Access='public'|'optional'|'user'|'operator'|'admin';
export interface Operation {
 method:'get'|'post'|'patch'|'delete'; path:string;procedure:ProcedureName;access:Access;
 bindings:Record<string,Binding>;sets:readonly string[];single?:readonly string[];
 currentCart?:boolean;idempotency?:{parameter:string;scope:string;uuid?:boolean;reference?:string};
 paymentAmount?:boolean;csrf?:boolean;status?:number;
}

import { z } from 'zod';
import { AppError } from '../utils/errors.js';
export function validate<T>(schema:z.ZodType<T>,value:unknown):T {
 const parsed=schema.safeParse(value);
 if(!parsed.success)throw new AppError(400,'VALIDATION_ERROR','Parámetros inválidos: '+[...new Set(parsed.error.issues.map(i=>i.path.join('.')||'solicitud'))].join(', '));
 return parsed.data;
}

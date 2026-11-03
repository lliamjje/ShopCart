export const roles=['Cliente','Operador','Administrador'] as const;
export type Role=typeof roles[number];
export interface Identity { id:string; sessionId:string; role:Role }
declare global { namespace Express { interface Request { identity?:Identity } } }
export {};

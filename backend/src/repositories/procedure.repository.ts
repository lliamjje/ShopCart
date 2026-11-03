import sql from 'mssql';
import { getPool } from '../config/database.js';
import { AppError, unavailable } from '../utils/errors.js';
import { bigintText,decimalInput,decimalOutput } from '../utils/numeric.js';
import { procedures,type ProcedureName,type ProcedureParameters,type ParameterDefinition,type SqlInput } from './storedProcedures.js';
import { sqlErrors } from './sqlErrors.js';
export type Row=Record<string,unknown>;
export interface ProcedureResult {recordsets:Row[][];output:Record<string,unknown>}
function sqlType(p:ParameterDefinition) {
 switch(p.type){
 case 'bigint':return sql.BigInt;case 'int':return sql.Int;case 'tinyint':return sql.TinyInt;case 'bit':return sql.Bit;
 case 'nvarchar':return sql.NVarChar(p.size==='max'?sql.MAX:Number(p.size));
 case 'varchar':return sql.VarChar(p.size==='max'?sql.MAX:Number(p.size));
 case 'varbinary':return sql.VarBinary(p.size==='max'?sql.MAX:Number(p.size));
 case 'binary':return sql.Binary;case 'decimal':return sql.Decimal(Number(p.size),Number(p.scale));
 case 'datetime2':return sql.DateTime2(Number(p.size));case 'uniqueidentifier':return sql.UniqueIdentifier;
 default:throw new AppError(500,'UNSUPPORTED_SQL_TYPE','Tipo SQL no configurado.');
 }
}
export async function executeProcedure<N extends ProcedureName>(name:N,parameters:ProcedureParameters[N]):Promise<ProcedureResult>{
 const defs:readonly ParameterDefinition[]=procedures[name].params;
 const values=parameters as Record<string,SqlInput|undefined>;
 for(const key of Object.keys(values))if(!defs.some(p=>p.name===key&&!p.output))throw new AppError(500,'SQL_CONTRACT_ERROR','Parámetro ajeno al contrato SQL.');
 try{
 const request=(await getPool()).request();
 for(const p of defs){
  if(p.output){request.output(p.name,sqlType(p));continue;}
  const value=values[p.name];
  if(value===undefined){if(p.optional)continue;throw new AppError(500,'SQL_CONTRACT_ERROR','Falta un parámetro SQL obligatorio.');}
  // Cada tipo se declara expresamente; IDs bigint nunca pasan por Number.
  request.input(p.name,sqlType(p),p.type==='decimal'&&value!==null?decimalInput(value):value);
 }
 const result=await request.execute<Row>('dbo.'+name);
 const sets=result.recordsets as sql.IRecordSet<Row>[];
 const recordsets=sets.map(set=>set.map(row=>{
  const normalized:Row={};
  for(const [key,value] of Object.entries(row)){
   const column=set.columns[key];
   if(value===null||value===undefined){normalized[key]=null;continue;}
   if(column?.type===sql.BigInt)normalized[key]=bigintText(value);
   else if(column?.type===sql.Decimal||column?.type===sql.Numeric)normalized[key]=decimalOutput(value,column.scale??4);
   else if(value instanceof Date)normalized[key]=value.toISOString();
   else normalized[key]=value;
  }
  return normalized;
 }));
 const output:Record<string,unknown>={};
 for(const p of defs.filter(d=>d.output)){
  const value:unknown=result.output[p.name];
  output[p.name]=value===null||value===undefined?null:p.type==='decimal'?decimalOutput(value,Number(p.scale)):
   p.type==='bigint'?bigintText(value):value instanceof Date?value.toISOString():value;
 }
 return {recordsets,output};
 }catch(error:unknown){
  if(error instanceof AppError)throw error;
  const e=error as {number?:number;code?:string;originalError?:{info?:{number?:number}}};
  const number=e.number??e.originalError?.info?.number;
  if(number===2812)throw new AppError(503,'SQL_PROCEDURE_NOT_INSTALLED','Procedimiento no instalado; aplique y verifique las migraciones SQL requeridas.');
  if(number===229)throw new AppError(503,'SQL_PERMISSIONS_REQUIRED','La cuenta de servicio no tiene los permisos SQL requeridos.');
  if(number===2601||number===2627)throw new AppError(409,'DUPLICATE_RESOURCE','El recurso o clave de operación ya existe.');
  if(number===547)throw new AppError(409,'SQL_INTEGRITY_CONFLICT','La operación incumple una restricción de integridad.');
  if(number===1205)throw new AppError(409,'RETRY_OPERATION','Conflicto concurrente; reintente con la misma clave de idempotencia.');
  if(number!==undefined&&sqlErrors[number]){const b=sqlErrors[number];throw new AppError(b.status,'SQL_'+number,b.message);}
  if(e.code==='ETIMEOUT'||e.code==='ELOGIN'||e.code==='ESOCKET'||e.code==='ECONNCLOSED'||e.code==='ENOTOPEN'||number===18456)throw unavailable();
  throw new AppError(503,'SQL_OPERATION_FAILED','No se pudo completar la operación SQL.');
 }
}
export function mappedCall<N extends ProcedureName>(name:N,parameters:Record<string,SqlInput|undefined>):Promise<ProcedureResult>{
 // Solo los mapeos estáticos del servidor invocan esta función; no acepta nombres HTTP.
 return executeProcedure(name,parameters as ProcedureParameters[N]);
}

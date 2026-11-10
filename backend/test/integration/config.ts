import { readFileSync, realpathSync } from 'node:fs';
import { resolve, relative, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'dotenv';

export const groups = ['smoke', 'auth', 'commerce', 'reports'] as const;
export type Group = typeof groups[number];
export interface IntegrationConfig {
  values: Record<string, string>;
  file: string;
  selected: Set<Group>;
}

// Función pura: se prueba sin importar la aplicación, conectar o leer secretos locales.
export function validateIsolation(values: Record<string, string>, developmentPort = '1433'): Set<Group> {
  const fail = (message: string): never => { throw new Error(`INTEGRACIÓN BLOQUEADA: ${message}`); };
  if (values.INTEGRATION_CONFIRM !== 'INSTANCIA_SQL_AISLADA_DESECHABLE')
    fail('confirme una instancia exclusiva de pruebas, nunca la base de desarrollo.');
  if (values.SQL_SERVER !== '127.0.0.1' || values.SQL_DATABASE !== 'ShopCart')
    fail('se requiere SQL_SERVER=127.0.0.1 y SQL_DATABASE=ShopCart en una instancia separada.');
  const port = Number(values.SQL_PORT);
  if (!/^\d+$/.test(values.SQL_PORT ?? '') || !Number.isInteger(port) || port < 1024 || port > 65535
      || port === 1433 || port === Number(developmentPort))
    fail('SQL_PORT debe ser explícito, distinto de 1433 y del puerto SQL de desarrollo.');
  if (values.NODE_ENV !== 'test') fail('NODE_ENV debe ser test.');
  if (values.SQL_USER !== 'shopcart_service') fail('use la cuenta shopcart_service con EXECUTE mínimo, sin privilegios administrativos.');
  if (!values.SQL_PASSWORD || (values.JWT_SECRET?.length ?? 0) < 32)
    fail('faltan SQL_PASSWORD o JWT_SECRET de pruebas.');
  if (values.SQL_ENCRYPT !== 'true' || !['true', 'false'].includes(values.SQL_TRUST_SERVER_CERTIFICATE ?? ''))
    fail('configure cifrado y validación de certificado explícitamente.');
  if (values.CORS_ORIGIN !== 'http://127.0.0.1:5173') fail('configure el origen local explícito de pruebas.');
  const names = (values.INTEGRATION_GROUPS ?? 'all').split(',');
  if (names.includes('all') && names.length !== 1) fail('all no se combina con otros grupos.');
  if (names[0] === 'all') return new Set(groups);
  if (names.some(name => !groups.includes(name as Group))) fail('grupos permitidos: all, smoke, auth, commerce, reports.');
  return new Set(names as Group[]);
}

export function loadIntegrationConfig(): IntegrationConfig {
  const supplied = process.env.SHOPCART_INTEGRATION_ENV;
  if (!supplied) throw new Error('INTEGRACIÓN BLOQUEADA: indique SHOPCART_INTEGRATION_ENV con una ruta a configuración externa de pruebas. No se carga backend/.env.');
  let file: string;
  let values: Record<string, string>;
  try {
    file = realpathSync(resolve(supplied));
    const project = realpathSync(fileURLToPath(new URL('../../../', import.meta.url)));
    const within = relative(project, file);
    if (!within.startsWith('..') && !isAbsolute(within)) throw new Error('configuración dentro del repositorio');
    // Impide señalar accidentalmente el archivo de desarrollo, incluso mediante enlaces.
    const developmentFile = fileURLToPath(new URL('../../.env', import.meta.url));
    let actualDevelopmentFile = developmentFile;
    try { actualDevelopmentFile = realpathSync(developmentFile); } catch { /* No existe .env local. */ }
    if (file.toLowerCase() === actualDevelopmentFile.toLowerCase())
      throw new Error('archivo de desarrollo');
    values = parse(readFileSync(file));
  } catch {
    throw new Error('INTEGRACIÓN BLOQUEADA: archivo externo ilegible o situado dentro del repositorio.');
  }
  let developmentPort = '1433';
  try {
    const development = parse(readFileSync(new URL('../../.env', import.meta.url)));
    developmentPort = development.SQL_PORT ?? '1433';
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT')
      throw new Error('INTEGRACIÓN BLOQUEADA: no se pudo verificar el puerto del .env de desarrollo.');
    // Sin .env se mantiene el puerto de desarrollo documentado.
  }
  // El selector puede variar por ejecución; las credenciales solo proceden del archivo.
  values.INTEGRATION_GROUPS = process.env.INTEGRATION_GROUPS ?? values.INTEGRATION_GROUPS ?? 'all';
  const selected = validateIsolation(values, developmentPort);
  return { file, values, selected };
}

export function applyIntegrationConfig(config: IntegrationConfig): void {
  // Se ejecuta ANTES del primer import de src. dotenv/config solo verá este archivo.
  for (const [key, value] of Object.entries(config.values)) process.env[key] = value;
  process.env.DOTENV_CONFIG_PATH = config.file;
  Object.assign(process.env, {
    NODE_ENV: 'test', HOST: '127.0.0.1', PORT: '3001',
    SQL_CONNECT_TIMEOUT_MS: '5000', SQL_REQUEST_TIMEOUT_MS: '15000',
    ACCESS_TOKEN_SECONDS: '600', SESSION_DAYS: '1',
  });
}

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateIsolation } from './integration/config.js';

const safe = {
  INTEGRATION_CONFIRM: 'INSTANCIA_SQL_AISLADA_DESECHABLE', NODE_ENV: 'test',
  SQL_SERVER: '127.0.0.1', SQL_PORT: '1434', SQL_DATABASE: 'ShopCart',
  SQL_USER: 'shopcart_service', SQL_PASSWORD: 'not-a-real-password',
  SQL_ENCRYPT: 'true', SQL_TRUST_SERVER_CERTIFICATE: 'true',
  CORS_ORIGIN: 'http://127.0.0.1:5173', JWT_SECRET: 'not-a-real-secret-for-offline-tests-only',
};
test('integración: configuración aislada permite seleccionar módulos sin conexiones', () => {
  assert.deepEqual([...validateIsolation({ ...safe, INTEGRATION_GROUPS: 'smoke,auth' })], ['smoke', 'auth']);
});
for (const [name, override] of Object.entries({
  'sin confirmación': { INTEGRATION_CONFIRM: '' },
  'puerto de desarrollo': { SQL_PORT: '1433' },
  'puerto ambiguo': { SQL_PORT: '' },
  'alias de servidor': { SQL_SERVER: 'localhost' },
  'base incompatible': { SQL_DATABASE: 'ShopCart_Test' },
  'cuenta administrativa': { SQL_USER: 'sa' },
  'secreto ausente': { SQL_PASSWORD: '' },
  'grupo desconocido': { INTEGRATION_GROUPS: 'unknown' },
  'selección ambigua': { INTEGRATION_GROUPS: 'all,auth' },
})) {
  test(`integración: bloquea ${name} antes de importar la API`, () => {
    assert.throws(() => validateIsolation({ ...safe, ...override }), /INTEGRACIÓN BLOQUEADA/);
  });
}
test('integración: bloquea también un puerto de desarrollo no estándar', () => {
  assert.throws(() => validateIsolation(safe, '1434'), /INTEGRACIÓN BLOQUEADA/);
});

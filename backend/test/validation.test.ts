import { test } from 'node:test';
import assert from 'node:assert/strict';
import { id, instant, revision, returnLines } from '../src/schemas/common.js';

test('IDs rechazan formatos inválidos sin lanzar y conservan bigint como texto', () => {
  for (const value of ['abc', '', '0', '-1', '1.5', '1e3', ' 1', '1 ', '01', '+1', '9223372036854775808', '99999999999999999999', 1, null]) {
    assert.doesNotThrow(() => assert.equal(id.safeParse(value).success, false, String(value)));
  }
  for (const value of ['1', '9007199254740993', '9223372036854775807']) assert.equal(id.parse(value), value);
});

test('IDs anidados en devoluciones también producen validación controlada', () => {
  assert.equal(returnLines.safeParse([{ orderItemId: 'abc', quantity: 1 }]).success, false);
  const valid = returnLines.parse([{ orderItemId: '9223372036854775807', quantity: 1 }]);
  assert.equal(JSON.parse(valid)[0].IdDetallePedido, '9223372036854775807');
});

test('fechas HTTP solo aceptan UTC Z con cero a tres decimales', () => {
  for (const value of ['2026-11-09T12:00:00Z', '2026-11-09T12:00:00.1Z', '2026-11-09T12:00:00.12Z', '2026-11-09T12:00:00.123Z']) {
    const result = instant.parse(value);
    assert.ok(result instanceof Date);
    assert.equal(result.getTime(), Date.parse(value));
  }
  for (const value of ['2026-11-09T12:00:00.1234Z', '2026-11-09T12:00:00.1234567Z', '2026-11-09T12:00:00+00:00', '2026-11-09T12:00:00-06:00', '2026-11-09T12:00:00', '2026-02-30T12:00:00Z', 'invalid']) {
    assert.equal(instant.safeParse(value).success, false, value);
  }
});

test('cartRevision mantiene sus siete decimales como texto SQL', () => {
  const value = '2026-11-09T12:00:00.1234567';
  assert.equal(revision.parse(value), value);
  assert.equal(revision.safeParse(value + 'Z').success, false);
  assert.equal(revision.safeParse(value + '8').success, false);
});

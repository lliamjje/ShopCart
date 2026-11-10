import assert from 'node:assert/strict';
export type Row = Record<string, unknown>;
export function object(value: unknown): Row {
  assert.ok(value !== null && typeof value === 'object' && !Array.isArray(value), 'Se esperaba un objeto HTTP.');
  return value as Row;
}
export function rows(value: unknown): Row[] {
  assert.ok(Array.isArray(value), 'Se esperaba una colección HTTP.');
  return value.map(object);
}
export function id(value: unknown): string {
  assert.equal(typeof value, 'string', 'bigint debe viajar como texto.');
  assert.match(value as string, /^[1-9]\d*$/);
  return value as string;
}
export function intId(value: unknown): number {
  assert.equal(typeof value, 'number');
  assert.ok(Number.isInteger(value) && Number(value) > 0);
  return value as number;
}
export function money(value: unknown): bigint {
  assert.equal(typeof value, 'string', 'Importes HTTP deben ser strings.');
  assert.match(value as string, /^-?\d+\.\d{4}$/);
  return BigInt((value as string).replace('.', ''));
}
export function state(value: unknown, expected: string): void { assert.equal(object(value).Estado, expected); }

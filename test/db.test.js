// src/models/db.js exports (contracts.md § 5) and the database tripwire in
// test/setup.js.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fakeDb, FAKE_DB_ERROR } from './helpers/db.js';
import { setNodeEnv } from './helpers/server.js';
import { takeTripwireHits } from './setup.js';

const restoreNodeEnv = setNodeEnv('test');
after(restoreNodeEnv);
const { query, checkConnection } = await import('../src/models/db.js');

test('query() passes the SQL text and the params array to the pool unchanged', async (t) => {
  const result = { rows: [{ n: 7 }], rowCount: 1 };
  const calls = fakeDb(t, () => result);
  const params = [7];
  const got = await query('SELECT $1::int AS n', params);
  assert.equal(got, result);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].text, 'SELECT $1::int AS n');
  assert.equal(calls[0].params, params);
});

test('query() lets a database error propagate to the caller', async (t) => {
  fakeDb(t, 'failing');
  await assert.rejects(query('SELECT 1'), { message: FAKE_DB_ERROR });
});

test('checkConnection() runs SELECT 1 and returns true when it succeeds', async (t) => {
  const calls = fakeDb(t, 'healthy');
  assert.equal(await checkConnection(), true);
  assert.deepEqual(calls.map((c) => c.text), ['SELECT 1']);
});

test('checkConnection() returns false and logs only the error message when it fails', async (t) => {
  fakeDb(t, 'failing');
  const logged = t.mock.method(console, 'error', () => {});
  assert.equal(await checkConnection(), false);
  assert.equal(logged.mock.callCount(), 1);
  assert.deepEqual(logged.mock.calls[0].arguments, ['Database connection check failed:', FAKE_DB_ERROR]);
});

test('the tripwire catches a query that reaches the real database', async (t) => {
  t.mock.method(console, 'error', () => {});
  // No fakeDb here on purpose. checkConnection swallows the tripwire's error,
  // so the hit count is what proves the tripwire fired.
  assert.equal(await checkConnection(), false);
  assert.equal(takeTripwireHits(), 1);
});

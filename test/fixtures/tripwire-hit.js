// A deliberately bad test: it reaches the database without fakeDb().
// test/tripwire.test.js runs this file in a child process and expects it to
// FAIL. Its name does not match *.test.js, so `npm test` never runs it directly.
import { test } from 'node:test';

process.env.NODE_ENV = 'test';
const { checkConnection } = await import('../../src/models/db.js');

test('forgets to fake the database', async (t) => {
  t.mock.method(console, 'error', () => {});
  await checkConnection();
});

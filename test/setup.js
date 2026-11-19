// Loaded into every test process by `npm test` (node --import ./test/setup.js).
//
// Database tripwire: no test may open a real database connection. Every real
// path (pool.query, pool.connect, a direct pg.Client) goes through
// Client.prototype.connect, so it is replaced here. A test that reaches it
// fails in the global afterEach below, even when the app code catches the
// error (checkConnection does, and would otherwise quietly return false).
// Tests fake the pool with test/helpers/db.js instead.
//
// test/tripwire.test.js proves a hit fails the test. Limit: a hit from work
// that outlives its test (an un-awaited query) is counted against the next
// test, or missed after a file's last test. Await every query in tests.
import { afterEach } from 'node:test';
import pg from 'pg';

let hits = 0;

pg.Client.prototype.connect = function tripwire(callback) {
  hits += 1;
  const err = new Error('Test tripwire: a test tried to open a real database connection. Use fakeDb() from test/helpers/db.js.');
  if (typeof callback === 'function') {
    process.nextTick(callback, err);
    return undefined;
  }
  return Promise.reject(err);
};

// Returns how many times the tripwire fired and resets the count.
// Only the tripwire's own self-test should call this.
export function takeTripwireHits() {
  const count = hits;
  hits = 0;
  return count;
}

afterEach(() => {
  const count = takeTripwireHits();
  if (count > 0) {
    throw new Error(`This test reached the real database ${count} time(s). Fake it with fakeDb() from test/helpers/db.js.`);
  }
});

// Fakes the database for one test by replacing pg.Pool.prototype.query, which
// the pool in src/models/db.js inherits. t.mock restores it after the test.
import pg from 'pg';

export const FAKE_DB_ERROR = 'fake: database unavailable';

// behaviour: 'healthy', 'failing', or a function (text, params) => result.
// Returns the list of calls, as { text, params }, in order.
export function fakeDb(t, behaviour) {
  let respond;
  if (behaviour === 'healthy') {
    respond = async () => ({ rows: [{ '?column?': 1 }], rowCount: 1 });
  } else if (behaviour === 'failing') {
    respond = async () => {
      throw new Error(FAKE_DB_ERROR);
    };
  } else if (typeof behaviour === 'function') {
    respond = async (text, params) => behaviour(text, params);
  } else {
    throw new TypeError(`fakeDb: unknown behaviour ${behaviour}`);
  }

  const calls = [];
  t.mock.method(pg.Pool.prototype, 'query', async (text, params) => {
    calls.push({ text, params });
    return respond(text, params);
  });
  return calls;
}

// The exported notFound and errorHandler (contracts.md § 3.3, M9, M10), run in
// a test-only app. No production route throws, so this app adds routes that
// do. Production routes are not changed to make errors testable.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { startServer, setNodeEnv } from './helpers/server.js';

const restoreNodeEnv = setNodeEnv('test');
const { default: app } = await import('../src/app.js');
const { notFound, errorHandler } = await import('../src/middleware/errorHandler.js');

const SERVER_MESSAGE = 'Something went wrong on our end. Please try again.';
const BAD_REQUEST_MESSAGE = 'That request couldn&#39;t be processed.';
const SECRET = 'internal detail that must not leak';

// Borrow the real app's views and Liquid engine so error pages render exactly
// as they do in production. Express keeps engines under their dotted
// extension; the first test fails loudly if that ever changes.
const testApp = express();
testApp.engine('liquid', app.engines['.liquid']);
testApp.set('views', app.get('views'));
testApp.set('view engine', 'liquid');
testApp.locals.siteName = app.locals.siteName;

testApp.get('/throw', () => {
  throw new Error(SECRET);
});
testApp.get('/reject', async () => {
  throw new Error(SECRET);
});
testApp.get('/status/:code', (req, res, next) => {
  const err = new Error(SECRET);
  if (req.params.code !== 'none') err.status = Number(req.params.code);
  next(err);
});
testApp.use(notFound);
testApp.use(errorHandler);

const server = await startServer(testApp);
after(async () => {
  await server.close();
  restoreNodeEnv();
});

test('the real app registers its Liquid engine under ".liquid"', () => {
  assert.equal(typeof app.engines['.liquid'], 'function');
});

test('errorHandler keeps four parameters, so Express treats it as an error handler (M10, I5)', () => {
  assert.equal(errorHandler.length, 4);
});

for (const path of ['/throw', '/reject']) {
  test(`an error from ${path} renders a 500 page with the public message and is logged`, async (t) => {
    const logged = t.mock.method(console, 'error', () => {});
    const res = await server.request('GET', path);
    assert.equal(res.status, 500);
    assert.equal(res.headers['content-type'], 'text/html; charset=utf-8');
    assert.match(res.body, /<title>Error \| Glucoscope<\/title>/);
    assert.match(res.body, /<h1>500: Error<\/h1>/);
    assert.ok(res.body.includes(SERVER_MESSAGE));
    assert.equal(logged.mock.callCount(), 1);
    assert.equal(logged.mock.calls[0].arguments[0].message, SECRET);
  });
}

for (const code of ['302', '600', 'none']) {
  test(`err.status ${code} is outside 400–599, so the response is 500`, async (t) => {
    t.mock.method(console, 'error', () => {});
    const res = await server.request('GET', `/status/${code}`);
    assert.equal(res.status, 500);
    assert.ok(res.body.includes(SERVER_MESSAGE));
  });
}

test('a 4xx err.status is kept, gets the 4xx message, and is not logged', async (t) => {
  const logged = t.mock.method(console, 'error', () => {});
  const res = await server.request('GET', '/status/418');
  assert.equal(res.status, 418);
  assert.match(res.body, /<h1>418: Error<\/h1>/);
  assert.ok(res.body.includes(BAD_REQUEST_MESSAGE));
  assert.equal(logged.mock.callCount(), 0);
});

test('every error page carries Cache-Control: private, no-store, set by the handler itself (§ 3.3, I3)', async (t) => {
  t.mock.method(console, 'error', () => {});
  // This app has no Cache-Control middleware, so the header must come from errorHandler.
  for (const path of ['/throw', '/status/418', '/nope']) {
    const res = await server.request('GET', path);
    assert.equal(res.headers['cache-control'], 'private, no-store', `${path} lacks the header`);
  }
});

test('outside production the stack is rendered', async (t) => {
  t.mock.method(console, 'error', () => {});
  const res = await server.request('GET', '/throw');
  assert.match(res.body, /<pre class="error-stack">/);
  assert.ok(res.body.includes(SECRET));
});

test('in production a 500 page shows no stack and no error message (I1, security negative case)', async (t) => {
  t.mock.method(console, 'error', () => {});
  // errorHandler reads NODE_ENV on every request.
  t.after(setNodeEnv('production'));
  const res = await server.request('GET', '/throw');
  assert.equal(res.status, 500);
  assert.ok(res.body.includes(SERVER_MESSAGE));
  assert.ok(!res.body.includes('error-stack'));
  assert.ok(!res.body.includes(SECRET));
});

test('when headers were already sent, errorHandler delegates to next(err) and renders nothing', () => {
  const err = new Error(SECRET);
  const fail = () => assert.fail('errorHandler must not touch a response that has started');
  const res = { headersSent: true, status: fail, render: fail, set: fail };
  let passedOn;
  errorHandler(err, {}, res, (e) => {
    passedOn = e;
  });
  assert.equal(passedOn, err);
});

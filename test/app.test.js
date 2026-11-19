// The real app in development mode: every route and global middleware
// contract in docs/contracts.md §§ 1–4.
import { test, after, mock } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { fakeDb, FAKE_DB_ERROR } from './helpers/db.js';
import { startServer, setNodeEnv } from './helpers/server.js';

// src/app.js reads NODE_ENV once, when it is imported (contracts.md § 7.1).
const restoreNodeEnv = setNodeEnv('test');

// I6: importing the app must not open a port.
const listen = mock.method(http.Server.prototype, 'listen');
const { default: app } = await import('../src/app.js');
const listenCallsDuringImport = listen.mock.callCount();
listen.mock.restore();

const server = await startServer(app);
after(async () => {
  await server.close();
  restoreNodeEnv();
});

// Liquid escapes the apostrophe in the public messages.
const NOT_FOUND_MESSAGE = 'We couldn&#39;t find that page.';
const BAD_REQUEST_MESSAGE = 'That request couldn&#39;t be processed.';
const NO_STORE = 'private, no-store';
const FORM = 'application/x-www-form-urlencoded';

const parserErrors = [
  {
    name: 'an oversized body',
    status: 413,
    headers: { 'content-type': FORM },
    body: `a=${'x'.repeat(110 * 1024)}`,
  },
  {
    name: 'an unsupported charset',
    status: 415,
    headers: { 'content-type': `${FORM}; charset=koi8-r` },
    body: 'a=b',
  },
  {
    name: 'a body that claims gzip but is not',
    status: 400,
    headers: { 'content-type': FORM, 'content-encoding': 'gzip' },
    body: 'a=b',
  },
];

test('importing src/app.js does not call listen (I6)', () => {
  assert.equal(listenCallsDuringImport, 0);
});

test('GET / renders the home page through the main layout (R1, § 4)', async () => {
  const res = await server.request('GET', '/');
  assert.equal(res.status, 200);
  assert.equal(res.headers['content-type'], 'text/html; charset=utf-8');
  assert.match(res.body, /<html lang="en">/);
  assert.match(res.body, /<title>Home \| Glucoscope<\/title>/);
  assert.match(res.body, /<link rel="stylesheet" href="\/css\/styles.css">/);
  assert.match(res.body, /<a class="site-header__brand" href="\/">Glucoscope<\/a>/);
  assert.match(res.body, /<nav aria-label="Main">\s*<a href="\/">Home<\/a>/);
  assert.match(res.body, /<h1>Your glucose data, in one clear view<\/h1>/);
  assert.match(res.body, /Glucoscope displays glucose data for information only and is not a medical device\./);
});

test('HEAD / answers 200 with no body', async () => {
  const res = await server.request('HEAD', '/');
  assert.equal(res.status, 200);
  assert.equal(res.body, '');
});

test('GET /health with a healthy database returns 200 {"status":"ok"} (R2)', async (t) => {
  const calls = fakeDb(t, 'healthy');
  const res = await server.request('GET', '/health');
  assert.equal(res.status, 200);
  assert.equal(res.headers['content-type'], 'application/json; charset=utf-8');
  assert.deepEqual(JSON.parse(res.body), { status: 'ok' });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].text, 'SELECT 1');
});

test('GET /health with a failing database returns 503 {"status":"unavailable"} and no detail (R2)', async (t) => {
  fakeDb(t, 'failing');
  t.mock.method(console, 'error', () => {});
  const res = await server.request('GET', '/health');
  assert.equal(res.status, 503);
  assert.deepEqual(JSON.parse(res.body), { status: 'unavailable' });
  assert.doesNotMatch(res.body, new RegExp(FAKE_DB_ERROR));
});

for (const [method, path] of [['GET', '/nope'], ['POST', '/']]) {
  test(`${method} ${path} renders the HTML 404 page (R5, § 3.3)`, async () => {
    const res = await server.request(method, path);
    assert.equal(res.status, 404);
    assert.equal(res.headers['content-type'], 'text/html; charset=utf-8');
    assert.match(res.body, /<title>Page not found \| Glucoscope<\/title>/);
    assert.match(res.body, /<h1>404: Page not found<\/h1>/);
    assert.ok(res.body.includes(NOT_FOUND_MESSAGE));
    assert.match(res.body, /<a href="\/">Back to home<\/a>/);
  });
}

test('a URL echoed in the development stack trace is HTML-escaped (I2)', async () => {
  const res = await server.request('GET', '/<script>x</script>');
  assert.equal(res.status, 404);
  assert.match(res.body, /<pre class="error-stack">/);
  assert.ok(res.body.includes('Not found: /&lt;script&gt;x&lt;/script&gt;'));
  assert.ok(!res.body.includes('<script>x'));
});

for (const c of parserErrors) {
  test(`${c.name} gets a ${c.status} error page with the public 4xx message (M6, § 3.3)`, async () => {
    const res = await server.request('POST', '/', { headers: c.headers, body: c.body });
    assert.equal(res.status, c.status);
    assert.match(res.body, new RegExp(`<h1>${c.status}: Error</h1>`));
    assert.ok(res.body.includes(BAD_REQUEST_MESSAGE));
  });
}

test('Cache-Control: private, no-store is on pages, /health and every error page (M7, I3)', async (t) => {
  fakeDb(t, 'healthy');
  const responses = [
    await server.request('GET', '/'),
    await server.request('GET', '/health'),
    await server.request('GET', '/nope'),
    await server.request('OPTIONS', '/'),
  ];
  for (const c of parserErrors) {
    responses.push(await server.request('POST', '/', { headers: c.headers, body: c.body }));
  }
  for (const res of responses) {
    assert.equal(res.headers['cache-control'], NO_STORE, `status ${res.status} lacks ${NO_STORE}`);
  }
});

test('static files are served at the root and are not marked no-store (R3, M5)', async () => {
  const res = await server.request('GET', '/css/styles.css');
  assert.equal(res.status, 200);
  assert.equal(res.headers['content-type'], 'text/css; charset=utf-8');
  assert.equal(res.headers['cache-control'], 'public, max-age=0');
});

test('GET /public/css/styles.css is a 404: there is no /public prefix (R3)', async () => {
  const res = await server.request('GET', '/public/css/styles.css');
  assert.equal(res.status, 404);
});

test('GET /css redirects to /css/ (R3)', async () => {
  const res = await server.request('GET', '/css');
  assert.equal(res.status, 301);
  assert.equal(res.headers.location, '/css/');
});

for (const path of ['/', '/health']) {
  test(`OPTIONS ${path} answers 200 and allows only GET and HEAD (R4)`, async () => {
    const res = await server.request('OPTIONS', path);
    assert.equal(res.status, 200);
    const allowed = res.headers.allow.split(',').map((m) => m.trim()).sort();
    assert.deepEqual(allowed, ['GET', 'HEAD']);
  });
}

test('no response carries X-Powered-By (M2)', async (t) => {
  fakeDb(t, 'healthy');
  const responses = [
    await server.request('GET', '/'),
    await server.request('GET', '/health'),
    await server.request('GET', '/nope'),
    await server.request('GET', '/css/styles.css'),
    await server.request('OPTIONS', '/'),
  ];
  for (const c of parserErrors) {
    responses.push(await server.request('POST', '/', { headers: c.headers, body: c.body }));
  }
  for (const res of responses) {
    assert.equal(res.headers['x-powered-by'], undefined, `status ${res.status} sent X-Powered-By`);
  }
});

test('trust proxy is off outside production (M4)', () => {
  assert.ok(!app.get('trust proxy'));
});

test('every template gets siteName (M3)', () => {
  assert.equal(app.locals.siteName, 'Glucoscope');
});

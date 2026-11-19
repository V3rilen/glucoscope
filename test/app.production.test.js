// The real app with NODE_ENV=production. It has its own file because
// src/app.js reads NODE_ENV once, when it is imported, and node --test runs
// each file in its own process.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, setNodeEnv } from './helpers/server.js';

const restoreNodeEnv = setNodeEnv('production');
const { default: app } = await import('../src/app.js');

const server = await startServer(app);
after(async () => {
  await server.close();
  restoreNodeEnv();
});

test('trust proxy is 1 in production (M4, I1)', () => {
  assert.equal(app.get('trust proxy'), 1);
});

test('the 404 page shows no stack and no internal message in production (§ 3.3, I1)', async () => {
  const res = await server.request('GET', '/<script>x</script>');
  assert.equal(res.status, 404);
  assert.ok(res.body.includes('We couldn&#39;t find that page.'));
  assert.ok(!res.body.includes('error-stack'));
  assert.ok(!res.body.includes('Not found:'));
  assert.ok(!res.body.includes('&lt;script'));
  assert.ok(!res.body.includes('x</script>'));
  assert.equal(res.headers['cache-control'], 'private, no-store');
});

test('a body-parser error page shows no stack in production (§ 3.3, I1)', async () => {
  const res = await server.request('POST', '/', {
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `a=${'x'.repeat(110 * 1024)}`,
  });
  assert.equal(res.status, 413);
  assert.ok(res.body.includes('That request couldn&#39;t be processed.'));
  assert.ok(!res.body.includes('error-stack'));
  assert.ok(!res.body.includes('PayloadTooLargeError'));
  assert.equal(res.headers['cache-control'], 'private, no-store');
});

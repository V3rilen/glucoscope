// Proves the database tripwire in test/setup.js turns a real-database hit into
// a FAILED test, on whatever Node version runs the suite (CI uses the engines
// floor). test/db.test.js only proves it counts hits.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';

const rootDir = path.join(import.meta.dirname, '..');

test('a test that reaches the real database fails', () => {
  // NODE_TEST_CONTEXT is set inside a test process. Without removing it, the
  // child runner would report to this process instead of running normally.
  const env = { ...process.env };
  delete env.NODE_TEST_CONTEXT;

  const child = spawnSync(
    process.execPath,
    ['--import', './test/setup.js', '--test', 'test/fixtures/tripwire-hit.js'],
    { cwd: rootDir, env, encoding: 'utf8', timeout: 60_000 },
  );

  const output = `${child.stdout}\n${child.stderr}`;
  assert.notEqual(child.status, 0, `the child run should fail:\n${output}`);
  assert.match(output, /reached the real database 1 time\(s\)/);
});

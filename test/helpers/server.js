// Runs an Express app on a loopback port for one test file and sends raw HTTP
// requests to it. node:http is used instead of fetch because fetch
// percent-encodes characters such as < in the path, and the escaping tests need
// the raw path to reach the app.
import http from 'node:http';
import { once } from 'node:events';

export async function startServer(app) {
  const server = http.createServer(app);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const { port } = server.address();

  return {
    request: (method, path, options) => request(port, method, path, options),
    async close() {
      server.closeAllConnections();
      server.close();
      await once(server, 'close');
    },
  };
}

// A request that gets no complete response within this time fails instead of
// hanging the run (node:test has no default timeout).
const REQUEST_TIMEOUT_MS = 10_000;

function request(port, method, path, { headers = {}, body } = {}) {
  const allHeaders = { ...headers };
  if (body !== undefined && allHeaders['content-length'] === undefined) {
    allHeaders['content-length'] = Buffer.byteLength(body);
  }

  return new Promise((resolve, reject) => {
    let responded = false;
    const req = http.request(
      { host: '127.0.0.1', port, method, path, headers: allHeaders, agent: false },
      (res) => {
        responded = true;
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (chunk) => {
          data += chunk;
        });
        res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: data }));
        res.on('error', reject);
        res.on('close', () => {
          if (!res.complete) reject(new Error(`${method} ${path}: the response was cut off`));
        });
      },
    );
    req.setTimeout(REQUEST_TIMEOUT_MS, () => {
      req.destroy(new Error(`${method} ${path}: no response within ${REQUEST_TIMEOUT_MS} ms`));
    });
    // When the app rejects a large body (413) it can answer and close the
    // socket while the body is still being sent. A socket error after the
    // response has arrived is expected then, so only earlier errors fail.
    req.on('error', (err) => {
      if (!responded) reject(err);
    });
    req.end(body);
  });
}

// Sets NODE_ENV for this test file and returns a function that puts it back.
// Deleting matters: assigning undefined would store the string "undefined".
export function setNodeEnv(value) {
  const previous = process.env.NODE_ENV;
  process.env.NODE_ENV = value;
  return () => {
    if (previous === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = previous;
  };
}

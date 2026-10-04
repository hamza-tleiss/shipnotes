import { test } from 'node:test';
import assert from 'node:assert/strict';
import pino from 'pino';
import { createApp } from '../src/app.js';

const silent = pino({ level: 'silent' });

function fakePool({ dbUp = true, rows = [] } = {}) {
  return {
    async query(sql, params = []) {
      if (!dbUp) throw new Error('connection refused');
      if (sql.startsWith('SELECT 1')) return { rows: [{ ok: 1 }] };
      if (sql.startsWith('INSERT')) {
        return {
          rows: [{ id: 1, title: params[0], body: params[1], created_at: '2026-01-01T00:00:00Z' }],
        };
      }
      if (sql.startsWith('DELETE')) return { rowCount: params[0] === 1 ? 1 : 0 };
      return { rows };
    },
  };
}

async function withServer(app, fn) {
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    await fn(base);
  } finally {
    await new Promise((r) => server.close(r));
  }
}

test('GET /health is ok even without a database', async () => {
  const app = createApp({ pool: fakePool({ dbUp: false }), logger: silent });
  await withServer(app, async (base) => {
    const res = await fetch(`${base}/health`);
    assert.equal(res.status, 200);
    const json = await res.json();
    assert.equal(json.status, 'ok');
  });
});

test('GET /ready is 503 when the database is down', async () => {
  const app = createApp({ pool: fakePool({ dbUp: false }), logger: silent });
  await withServer(app, async (base) => {
    const res = await fetch(`${base}/ready`);
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { status: 'not_ready', db: 'down' });
  });
});

test('GET /api/notes returns the list', async () => {
  const rows = [{ id: 7, title: 'hello', body: '', created_at: '2026-01-01T00:00:00Z' }];
  const app = createApp({ pool: fakePool({ rows }), logger: silent });
  await withServer(app, async (base) => {
    const res = await fetch(`${base}/api/notes`);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), rows);
  });
});

test('POST /api/notes rejects a missing title', async () => {
  const app = createApp({ pool: fakePool(), logger: silent });
  await withServer(app, async (base) => {
    const res = await fetch(`${base}/api/notes`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ body: 'no title' }),
    });
    assert.equal(res.status, 400);
  });
});

test('POST /api/notes creates a note', async () => {
  const app = createApp({ pool: fakePool(), logger: silent });
  await withServer(app, async (base) => {
    const res = await fetch(`${base}/api/notes`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ title: 'Ship it', body: 'first note' }),
    });
    assert.equal(res.status, 201);
    const json = await res.json();
    assert.equal(json.title, 'Ship it');
  });
});

test('DELETE /api/notes/:id returns 404 for unknown id', async () => {
  const app = createApp({ pool: fakePool(), logger: silent });
  await withServer(app, async (base) => {
    const res = await fetch(`${base}/api/notes/999`, { method: 'DELETE' });
    assert.equal(res.status, 404);
  });
});

test('GET /metrics exposes prometheus text', async () => {
  const app = createApp({ pool: fakePool(), logger: silent });
  await withServer(app, async (base) => {
    await fetch(`${base}/health`);
    const res = await fetch(`${base}/metrics`);
    assert.equal(res.status, 200);
    const text = await res.text();
    assert.match(text, /http_requests_total/);
  });
});

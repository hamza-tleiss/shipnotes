import express from 'express';
import pinoHttp from 'pino-http';
import client from 'prom-client';
import { config } from './config.js';

// createApp receives its dependencies so tests can inject a fake pool.
export function createApp({ pool, logger }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '100kb' }));
  app.use(
    pinoHttp({
      logger,
      // Keep health-check noise out of the logs.
      autoLogging: { ignore: (req) => ['/health', '/ready', '/metrics'].includes(req.url) },
    }),
  );

  // ---- Metrics (Prometheus scrapes GET /metrics) --------------------------
  const register = new client.Registry();
  register.setDefaultLabels({ app: 'shipnotes-api', version: config.appVersion });
  client.collectDefaultMetrics({ register });

  const httpRequestsTotal = new client.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'status'],
    registers: [register],
  });
  const httpRequestDuration = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request latency in seconds',
    labelNames: ['method', 'route', 'status'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
    registers: [register],
  });

  app.use((req, res, next) => {
    if (req.path === '/metrics') return next();
    const stop = httpRequestDuration.startTimer();
    res.on('finish', () => {
      const route = req.route?.path ?? req.path;
      const labels = { method: req.method, route, status: String(res.statusCode) };
      httpRequestsTotal.inc(labels);
      stop(labels);
    });
    next();
  });

  // ---- Probes ------------------------------------------------------------
  // Liveness: "is the process alive?" Never depends on the database.
  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', version: config.appVersion, uptime: Math.round(process.uptime()) });
  });

  // Readiness: "can I serve traffic?" Depends on the database.
  app.get('/ready', async (_req, res) => {
    try {
      await pool.query('SELECT 1');
      res.json({ status: 'ready', db: 'up' });
    } catch (err) {
      logger.warn({ err: err.message }, 'readiness check failed');
      res.status(503).json({ status: 'not_ready', db: 'down' });
    }
  });

  app.get('/metrics', async (_req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  // ---- Business endpoints -------------------------------------------------
  app.get('/api/notes', async (_req, res, next) => {
    try {
      const { rows } = await pool.query(
        'SELECT id, title, body, created_at FROM notes ORDER BY created_at DESC LIMIT 100',
      );
      res.json(rows);
    } catch (err) {
      next(err);
    }
  });

  app.post('/api/notes', async (req, res, next) => {
    const title = typeof req.body?.title === 'string' ? req.body.title.trim() : '';
    const body = typeof req.body?.body === 'string' ? req.body.body : '';
    if (!title) return res.status(400).json({ error: 'title is required' });
    if (title.length > 200) return res.status(400).json({ error: 'title too long (max 200)' });
    try {
      const { rows } = await pool.query(
        'INSERT INTO notes (title, body) VALUES ($1, $2) RETURNING id, title, body, created_at',
        [title, body],
      );
      res.status(201).json(rows[0]);
    } catch (err) {
      next(err);
    }
  });

  app.delete('/api/notes/:id', async (req, res, next) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ error: 'invalid id' });
    try {
      const { rowCount } = await pool.query('DELETE FROM notes WHERE id = $1', [id]);
      if (rowCount === 0) return res.status(404).json({ error: 'not found' });
      res.status(204).end();
    } catch (err) {
      next(err);
    }
  });

  app.use((_req, res) => res.status(404).json({ error: 'route not found' }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, _next) => {
    req.log?.error({ err }, 'unhandled error');
    res.status(500).json({ error: 'internal error' });
  });

  return app;
}
const = ;

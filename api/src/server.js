import { createApp } from './app.js';
import { createPool } from './db.js';
import { migrateWithRetry } from './migrate.js';
import { logger } from './logger.js';
import { config } from './config.js';

const pool = createPool();

if (config.skipMigrate) {
  logger.info('SKIP_MIGRATE=true, assuming schema is managed externally');
} else {
  const ok = await migrateWithRetry(pool, logger);
  if (!ok) logger.error('could not migrate; API will report not ready until the database is reachable');
}

const app = createApp({ pool, logger });
const server = app.listen(config.port, () => {
  logger.info(
    { port: config.port, env: config.nodeEnv, version: config.appVersion },
    'shipnotes-api listening',
  );
});

// Graceful shutdown: Kubernetes sends SIGTERM, waits, then SIGKILL.
// Finishing in-flight requests here is what makes zero-downtime deploys real.
function shutdown(signal) {
  logger.info({ signal }, 'shutting down');
  server.close(async () => {
    await pool.end();
    logger.info('closed cleanly');
    process.exit(0);
  });
  setTimeout(() => {
    logger.error('forced exit after timeout');
    process.exit(1);
  }, 10_000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

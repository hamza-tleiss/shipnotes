// Idempotent schema migration. Safe to run many times (CREATE ... IF NOT EXISTS).
export async function migrate(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS notes (
      id         SERIAL PRIMARY KEY,
      title      TEXT NOT NULL,
      body       TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Databases usually start slower than the API. Retrying instead of crashing is
// the difference between "works on my machine" and "works in a cluster".
export async function migrateWithRetry(pool, logger, { attempts = 10, delayMs = 2000 } = {}) {
  for (let i = 1; i <= attempts; i++) {
    try {
      await migrate(pool);
      logger.info({ attempt: i }, 'database schema is ready');
      return true;
    } catch (err) {
      logger.warn({ attempt: i, attempts, err: err.message }, 'migration failed, retrying');
      if (i === attempts) return false;
      await sleep(delayMs);
    }
  }
  return false;
}

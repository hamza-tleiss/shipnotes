// Run with: npm run migrate
// Used later as a Kubernetes Job / init container so the API image never needs DDL rights.
import { createPool } from './db.js';
import { migrateWithRetry } from './migrate.js';
import { logger } from './logger.js';

const pool = createPool();
const ok = await migrateWithRetry(pool, logger, { attempts: 15, delayMs: 2000 });
await pool.end();
process.exit(ok ? 0 : 1);

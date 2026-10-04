import pg from 'pg';
import { config } from './config.js';

export function createPool(connectionString = config.databaseUrl) {
  return new pg.Pool({
    connectionString,
    max: 10,
    connectionTimeoutMillis: 5000,
  });
}

import pino from 'pino';
import { config } from './config.js';

// JSON logs on stdout. Containers and log collectors (Loki, CloudWatch) expect exactly this.
export const logger = pino({ level: config.logLevel });

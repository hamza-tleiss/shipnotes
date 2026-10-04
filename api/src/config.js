// Every setting the API needs comes from the environment.
// This is the 12-factor rule: same image everywhere, config injected at runtime.
export const config = {
  port: Number(process.env.PORT ?? 3000),
  databaseUrl:
    process.env.DATABASE_URL ??
    'postgres://shipnotes:shipnotes@localhost:5432/shipnotes',
  nodeEnv: process.env.NODE_ENV ?? 'development',
  logLevel: process.env.LOG_LEVEL ?? 'info',
  appVersion: process.env.APP_VERSION ?? 'dev',
  // Set SKIP_MIGRATE=true when a separate job (init container, CI step) owns migrations.
  skipMigrate: process.env.SKIP_MIGRATE === 'true',
};

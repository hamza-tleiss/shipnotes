-- Runs automatically the FIRST time the postgres container starts
-- (mounted into /docker-entrypoint-initdb.d/). It is idempotent on purpose.
CREATE TABLE IF NOT EXISTS notes (
  id         SERIAL PRIMARY KEY,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO notes (title, body)
SELECT 'Welcome to ShipNotes', 'This row was seeded by db/init.sql. Delete me when you like.'
WHERE NOT EXISTS (SELECT 1 FROM notes);

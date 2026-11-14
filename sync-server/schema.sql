-- One row per sync group. `blob` is the group's encrypted dictionary and snippets (base64); the
-- server can't read it. `auth_hash` is the SHA-256 of the token the first writer used.
CREATE TABLE IF NOT EXISTS groups (
  id TEXT PRIMARY KEY,
  auth_hash TEXT NOT NULL,
  version INTEGER NOT NULL,
  blob TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

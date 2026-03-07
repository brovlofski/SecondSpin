'use strict';

/**
 * database.js
 *
 * Initialises and exports the SQLite database instance using Node.js's
 * built-in `node:sqlite` module (stable in Node ≥ 22.5, no native compilation
 * required — replaces the previous better-sqlite3 dependency).
 *
 * Schema:
 *   album_mapping
 *   ├── id                  INTEGER PRIMARY KEY AUTOINCREMENT
 *   ├── discogs_release_id  INTEGER UNIQUE   — Discogs release ID (NULL = artist+album only lookup)
 *   ├── lookup_key          TEXT    UNIQUE   — "artist::album" fallback key (lowercase)
 *   ├── netease_album_id    INTEGER          — NULL means "no match found"
 *   ├── netease_album_name  TEXT
 *   ├── confidence          REAL             — composite score in [0, 1]
 *   ├── deeplink            TEXT             — orpheus://album/{id} or NULL
 *   ├── verified            INTEGER DEFAULT 0 — 1 = manually confirmed
 *   └── created_at          TEXT             — ISO 8601 timestamp
 */

const path = require('path');
const fs   = require('fs');

// node:sqlite is built into Node ≥ 22.5 — no npm package required
const { DatabaseSync } = require('node:sqlite');

// ---------------------------------------------------------------------------
// Resolve database path
// ---------------------------------------------------------------------------
const dbPath = process.env.DB_PATH
  ? path.resolve(process.env.DB_PATH)
  : path.resolve(__dirname, '../../data/mappings.db');

// Ensure the data directory exists
const dbDir = path.dirname(dbPath);
if (!fs.existsSync(dbDir)) {
  fs.mkdirSync(dbDir, { recursive: true });
}

// ---------------------------------------------------------------------------
// Open database
// ---------------------------------------------------------------------------
const db = new DatabaseSync(dbPath);

// Performance & safety pragmas
// node:sqlite uses db.exec() for pragmas (no db.pragma() method)
db.exec('PRAGMA journal_mode = WAL');
db.exec('PRAGMA synchronous = NORMAL');
db.exec('PRAGMA foreign_keys = ON');

// ---------------------------------------------------------------------------
// DDL — create tables and indexes
// ---------------------------------------------------------------------------
db.exec(`
  CREATE TABLE IF NOT EXISTS album_mapping (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    discogs_release_id INTEGER,
    lookup_key         TEXT,
    netease_album_id   INTEGER,
    netease_album_name TEXT,
    confidence         REAL,
    deeplink           TEXT,
    verified           INTEGER DEFAULT 0,
    created_at         TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE (discogs_release_id),
    UNIQUE (lookup_key)
  );

  CREATE INDEX IF NOT EXISTS idx_mapping_discogs_id
    ON album_mapping(discogs_release_id);

  CREATE INDEX IF NOT EXISTS idx_mapping_lookup_key
    ON album_mapping(lookup_key);
`);

module.exports = db;
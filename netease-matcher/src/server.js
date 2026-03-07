'use strict';

/**
 * server.js
 *
 * Express HTTP server entry-point for the netease-matcher microservice.
 *
 * Endpoints:
 *   POST   /match           — run the album-matching pipeline
 *   GET    /match/cache     — list cached mappings
 *   DELETE /match/cache/:id — evict a cached mapping
 *   GET    /health          — liveness check
 *
 * Configuration (environment variables):
 *   PORT                  — HTTP port (default 3002)
 *   NETEASE_API_BASE_URL  — NeteaseCloudMusicApi proxy URL (optional)
 *   DB_PATH               — SQLite database file path (optional)
 *   MATCH_THRESHOLD       — minimum confidence to accept a match (default 0.75)
 *   MUSICBRAINZ_APP_NAME  — User-Agent app name for MusicBrainz API
 *   MUSICBRAINZ_CONTACT   — User-Agent contact for MusicBrainz API
 */

require('dotenv').config();

const express    = require('express');
const matchRoute = require('./routes/match');

const app  = express();
const PORT = parseInt(process.env.PORT || '3002', 10);

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------

// Parse JSON request bodies
app.use(express.json({ limit: '1mb' }));

// Simple request logger
app.use((req, _res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

app.use('/match', matchRoute);

// Health / liveness check
app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'netease-matcher',
    timestamp: new Date().toISOString(),
  });
});

// 404 handler
app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Global error handler
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error('[Server] Unhandled error:', err);
  res.status(500).json({ error: 'Internal server error', detail: err.message });
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

app.listen(PORT, () => {
  console.log(`[netease-matcher] Listening on http://localhost:${PORT}`);
  console.log(`  NETEASE_API_BASE_URL : ${process.env.NETEASE_API_BASE_URL || '(direct mode)'}`);
  console.log(`  MATCH_THRESHOLD      : ${process.env.MATCH_THRESHOLD || '0.75'}`);
  console.log(`  DB_PATH              : ${process.env.DB_PATH || '(default)'}`);
});

module.exports = app; // exported for testing
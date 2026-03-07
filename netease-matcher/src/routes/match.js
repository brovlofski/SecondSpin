'use strict';

/**
 * routes/match.js
 *
 * Express router for the /match endpoint.
 *
 * POST /match
 * -----------
 * Request body (JSON):
 *   {
 *     "discogs_release_id": 12345,   // optional
 *     "artist":   "Daft Punk",       // required
 *     "album":    "Random Access Memories", // required
 *     "year":     2013,              // optional
 *     "tracklist": ["Get Lucky", ...]  // optional — improves scoring
 *   }
 *
 * Response 200 — matched:
 *   {
 *     "matched":            true,
 *     "netease_album_id":   18868683,
 *     "netease_album_name": "Random Access Memories",
 *     "confidence":         0.921,
 *     "deeplink":           "orpheus://album/18868683"
 *   }
 *
 * Response 200 — no match:
 *   { "matched": false }
 *
 * Response 400 — bad input:
 *   { "error": "<message>" }
 *
 * GET /match/cache
 * ----------------
 * Returns all cached mappings (for debugging / admin).
 * Query params: ?limit=100
 *
 * DELETE /match/cache/:discogsId
 * --------------------------------
 * Evict a single entry by Discogs release ID.
 */

const express         = require('express');
const { matchAlbum }  = require('../services/matcherService');
const repo            = require('../db/mappingRepository');

const router = express.Router();

// ---------------------------------------------------------------------------
// POST /match — run the full pipeline
// ---------------------------------------------------------------------------
router.post('/', async (req, res) => {
  const { discogs_release_id, artist, album, year, tracklist } = req.body ?? {};

  // Input validation
  if (!artist || typeof artist !== 'string' || artist.trim() === '') {
    return res.status(400).json({ error: '"artist" is required and must be a non-empty string' });
  }
  if (!album || typeof album !== 'string' || album.trim() === '') {
    return res.status(400).json({ error: '"album" is required and must be a non-empty string' });
  }

  try {
    const result = await matchAlbum({
      discogs_release_id: discogs_release_id ? Number(discogs_release_id) : null,
      artist: artist.trim(),
      album:  album.trim(),
      year:   year ? Number(year) : null,
      tracklist: Array.isArray(tracklist) ? tracklist : [],
    });

    return res.json(result);
  } catch (err) {
    console.error('[Route /match] Unexpected error:', err);
    return res.status(500).json({ error: 'Internal server error', detail: err.message });
  }
});

// ---------------------------------------------------------------------------
// GET /match/cache — list cached mappings
// ---------------------------------------------------------------------------
router.get('/cache', (req, res) => {
  const limit = Math.min(parseInt(req.query.limit || '100', 10), 1000);
  try {
    const rows = repo.listAll(limit);
    return res.json({ count: rows.length, items: rows });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

// ---------------------------------------------------------------------------
// DELETE /match/cache/:discogsId — evict a cached mapping
// ---------------------------------------------------------------------------
router.delete('/cache/:discogsId', (req, res) => {
  const id = parseInt(req.params.discogsId, 10);
  if (!id || isNaN(id)) {
    return res.status(400).json({ error: 'Invalid discogsId' });
  }
  try {
    repo.deleteByDiscogsId(id);
    return res.json({ deleted: true, discogs_release_id: id });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

module.exports = router;
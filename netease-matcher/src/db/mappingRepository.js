'use strict';

/**
 * mappingRepository.js
 *
 * Data-access layer for the album_mapping table.
 * All queries are synchronous (better-sqlite3 style) which is appropriate
 * here because the DB operations are fast and the bottleneck is always
 * the external network calls (MusicBrainz, NetEase).
 */

const db = require('./database');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Build the lookup key used as a fallback when no discogs_release_id is
 * available (or when we want to avoid redundant API calls for the same
 * artist+album combination).
 *
 * @param {string} artist
 * @param {string} album
 * @returns {string}  e.g. "daft punk::random access memories"
 */
function makeLookupKey(artist, album) {
  return `${(artist || '').toLowerCase().trim()}::${(album || '').toLowerCase().trim()}`;
}

// ---------------------------------------------------------------------------
// Read
// ---------------------------------------------------------------------------

/**
 * Find a cached mapping by Discogs release ID.
 *
 * @param {number} discogsReleaseId
 * @returns {object|null}
 */
function findByDiscogsId(discogsReleaseId) {
  if (!discogsReleaseId) return null;
  return db
    .prepare('SELECT * FROM album_mapping WHERE discogs_release_id = ?')
    .get(discogsReleaseId) ?? null;
}

/**
 * Find a cached mapping by artist+album lookup key (case-insensitive).
 *
 * @param {string} artist
 * @param {string} album
 * @returns {object|null}
 */
function findByLookupKey(artist, album) {
  const key = makeLookupKey(artist, album);
  return db
    .prepare('SELECT * FROM album_mapping WHERE lookup_key = ?')
    .get(key) ?? null;
}

/**
 * Find a cached mapping by NetEase album ID.
 *
 * @param {number} neteaseAlbumId
 * @returns {object|null}
 */
function findByNeteaseId(neteaseAlbumId) {
  if (!neteaseAlbumId) return null;
  return db
    .prepare('SELECT * FROM album_mapping WHERE netease_album_id = ?')
    .get(neteaseAlbumId) ?? null;
}

/**
 * Return all stored mappings (for debugging / listing).
 *
 * @param {number} [limit=100]
 * @returns {object[]}
 */
function listAll(limit = 100) {
  return db
    .prepare('SELECT * FROM album_mapping ORDER BY created_at DESC LIMIT ?')
    .all(limit);
}

// ---------------------------------------------------------------------------
// Write
// ---------------------------------------------------------------------------

/**
 * Upsert a mapping result. Uses INSERT OR REPLACE keyed on discogs_release_id
 * when available, otherwise on lookup_key.
 *
 * @param {object} params
 * @param {number|null} params.discogsReleaseId
 * @param {string}      params.artist
 * @param {string}      params.album
 * @param {number|null} params.neteaseAlbumId      — null = "no match"
 * @param {string|null} params.neteaseAlbumName
 * @param {number}      params.confidence
 * @param {string|null} params.deeplink
 * @returns {object} the row as saved
 */
function upsert({
  discogsReleaseId,
  artist,
  album,
  neteaseAlbumId,
  neteaseAlbumName,
  confidence,
  deeplink,
}) {
  const lookupKey = makeLookupKey(artist, album);

  db.prepare(`
    INSERT INTO album_mapping
      (discogs_release_id, lookup_key, netease_album_id, netease_album_name,
       confidence, deeplink, verified, created_at)
    VALUES (?, ?, ?, ?, ?, ?, 0, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
    ON CONFLICT(discogs_release_id) DO UPDATE SET
      lookup_key         = excluded.lookup_key,
      netease_album_id   = excluded.netease_album_id,
      netease_album_name = excluded.netease_album_name,
      confidence         = excluded.confidence,
      deeplink           = excluded.deeplink,
      created_at         = excluded.created_at
  `).run(
    discogsReleaseId ?? null,
    lookupKey,
    neteaseAlbumId ?? null,
    neteaseAlbumName ?? null,
    confidence,
    deeplink ?? null,
  );

  // Also upsert by lookup_key for artist+album lookups without a discogs ID
  if (!discogsReleaseId) {
    db.prepare(`
      INSERT INTO album_mapping
        (discogs_release_id, lookup_key, netease_album_id, netease_album_name,
         confidence, deeplink, verified, created_at)
      VALUES (NULL, ?, ?, ?, ?, ?, 0, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
      ON CONFLICT(lookup_key) DO UPDATE SET
        netease_album_id   = excluded.netease_album_id,
        netease_album_name = excluded.netease_album_name,
        confidence         = excluded.confidence,
        deeplink           = excluded.deeplink,
        created_at         = excluded.created_at
    `).run(
      lookupKey,
      neteaseAlbumId ?? null,
      neteaseAlbumName ?? null,
      confidence,
      deeplink ?? null,
    );
  }

  return findByLookupKey(artist, album);
}

/**
 * Mark a mapping as manually verified (verified = 1).
 *
 * @param {number} id  — primary key
 */
function markVerified(id) {
  db.prepare('UPDATE album_mapping SET verified = 1 WHERE id = ?').run(id);
}

/**
 * Delete a mapping by Discogs release ID.
 *
 * @param {number} discogsReleaseId
 */
function deleteByDiscogsId(discogsReleaseId) {
  db.prepare('DELETE FROM album_mapping WHERE discogs_release_id = ?').run(discogsReleaseId);
}

module.exports = {
  makeLookupKey,
  findByDiscogsId,
  findByLookupKey,
  findByNeteaseId,
  listAll,
  upsert,
  markVerified,
  deleteByDiscogsId,
};
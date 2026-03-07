'use strict';

/**
 * matcherService.js
 *
 * Orchestrates the full album-matching pipeline:
 *
 *   1. Check SQLite cache — return immediately if found.
 *   2. Normalize input (strip edition suffixes, lowercase, etc.).
 *   3. Query MusicBrainz to enrich track count / canonical year.
 *   4. Search NetEase Cloud Music for candidate albums.
 *   5. Score each candidate with the weighted Jaro-Winkler formula.
 *   6. Accept the best candidate if score ≥ MATCH_THRESHOLD (default 0.75).
 *   7. Persist result (match or "no match") to SQLite.
 *   8. Return the API response object.
 *
 * This file is the single authoritative place for matching logic so that
 * both the HTTP route and any future CLI/batch runner can share it.
 */

const { normalizeTitle, normalizeArtist } = require('../utils/normalize');
const { computeScore }                    = require('../utils/scoring');
const musicbrainzService                  = require('./musicbrainzService');
const neteaseService                      = require('./neteaseService');
const repo                                = require('../db/mappingRepository');

// Threshold below which we consider the match unreliable
const MATCH_THRESHOLD = parseFloat(process.env.MATCH_THRESHOLD || '0.75');

// ---------------------------------------------------------------------------
// Deeplink builder
// ---------------------------------------------------------------------------

/**
 * Build the NetEase album deeplink.
 * orpheus:// is the registered URL scheme used by NetEase Cloud Music iOS app.
 *
 * @param {number} albumId
 * @returns {string}
 */
function buildDeeplink(albumId) {
  return `orpheus://album/${albumId}`;
}

// ---------------------------------------------------------------------------
// Cache → response converter
// ---------------------------------------------------------------------------

/**
 * Convert a database row into the standard API response shape.
 *
 * @param {object} row
 * @returns {object}
 */
function rowToResponse(row) {
  if (!row.netease_album_id) {
    return { matched: false, cached: true };
  }
  return {
    matched:            true,
    cached:             true,
    netease_album_id:   row.netease_album_id,
    netease_album_name: row.netease_album_name,
    confidence:         row.confidence,
    deeplink:           row.deeplink,
  };
}

// ---------------------------------------------------------------------------
// Main pipeline
// ---------------------------------------------------------------------------

/**
 * Match a Discogs release to a NetEase album.
 *
 * @param {object} input
 * @param {number|null} input.discogs_release_id
 * @param {string}      input.artist
 * @param {string}      input.album
 * @param {number|null} [input.year]
 * @param {string[]}    [input.tracklist]
 * @returns {Promise<object>} API response
 */
async function matchAlbum({ discogs_release_id, artist, album, year, tracklist }) {
  const ts = () => new Date().toISOString();

  console.log(`[${ts()}] [Matcher] Starting match: "${artist} — ${album}" (discogsId=${discogs_release_id ?? 'none'})`);

  // -------------------------------------------------------------------------
  // STEP 0: Cache check
  // -------------------------------------------------------------------------
  const cached = discogs_release_id
    ? repo.findByDiscogsId(discogs_release_id)
    : repo.findByLookupKey(artist, album);

  if (cached) {
    console.log(`[${ts()}] [Matcher] Cache hit (id=${cached.id}, confidence=${cached.confidence})`);
    return rowToResponse(cached);
  }

  // -------------------------------------------------------------------------
  // STEP 1: Normalize input
  // -------------------------------------------------------------------------
  const normInputTitle  = normalizeTitle(album);
  const normInputArtist = normalizeArtist(artist);
  const inputTrackCount = Array.isArray(tracklist) && tracklist.length > 0
    ? tracklist.length
    : null;

  console.log(`[${ts()}] [Matcher] Normalized: title="${normInputTitle}" artist="${normInputArtist}" tracks=${inputTrackCount ?? '?'}`);

  // -------------------------------------------------------------------------
  // STEP 2: Enrich from MusicBrainz (non-blocking — failure is graceful)
  // -------------------------------------------------------------------------
  let enrichedYear       = year ?? null;
  let enrichedTrackCount = inputTrackCount;

  try {
    const mb = await musicbrainzService.searchRelease(artist, album);
    if (mb) {
      console.log(`[${ts()}] [MusicBrainz] Found: "${mb.title}" (year=${mb.year}, tracks=${mb.trackCount})`);
      // Prefer MusicBrainz track count if the input tracklist is absent
      if (!enrichedTrackCount && mb.trackCount) enrichedTrackCount = mb.trackCount;
      // Prefer MusicBrainz year if not provided directly
      if (!enrichedYear && mb.year) enrichedYear = mb.year;
    }
  } catch (err) {
    // MusicBrainz failure does not abort the pipeline
    console.warn(`[${ts()}] [MusicBrainz] Skipped due to error: ${err.message}`);
  }

  const releaseProfile = {
    normTitle:   normInputTitle,
    normArtist:  normInputArtist,
    year:        enrichedYear,
    trackCount:  enrichedTrackCount,
  };

  // -------------------------------------------------------------------------
  // STEP 3: Search NetEase
  // -------------------------------------------------------------------------
  const candidates = await neteaseService.searchAlbums(artist, album);
  console.log(`[${ts()}] [NetEase] ${candidates.length} candidates returned`);

  if (candidates.length === 0) {
    console.log(`[${ts()}] [Matcher] No NetEase candidates — storing negative cache`);
    repo.upsert({
      discogsReleaseId: discogs_release_id ?? null,
      artist, album,
      neteaseAlbumId:   null,
      neteaseAlbumName: null,
      confidence:       0,
      deeplink:         null,
    });
    return { matched: false };
  }

  // -------------------------------------------------------------------------
  // STEP 4 & 5: Score candidates
  // -------------------------------------------------------------------------
  let bestCandidate  = null;
  let bestScore      = -1;
  let bestBreakdown  = null;

  for (const candidate of candidates) {
    const normCandTitle  = normalizeTitle(candidate.name);
    const normCandArtist = normalizeArtist(candidate.artist);

    const { score, breakdown } = computeScore(
      {
        normTitle:   normCandTitle,
        normArtist:  normCandArtist,
        year:        candidate.year,
        trackCount:  candidate.trackCount,
      },
      releaseProfile,
    );

    console.log(
      `[${ts()}] [Matcher] Candidate id=${candidate.id} ` +
      `"${candidate.name}" by "${candidate.artist}" ` +
      `→ score=${score} ` +
      `(title=${breakdown.titleSim.toFixed(3)}, ` +
      `artist=${breakdown.artistSim.toFixed(3)}, ` +
      `tracks=${breakdown.trackSc}, year=${breakdown.yearSc})`,
    );

    if (score > bestScore) {
      bestScore     = score;
      bestCandidate = candidate;
      bestBreakdown = breakdown;
    }
  }

  // -------------------------------------------------------------------------
  // STEP 6: Threshold gate
  // -------------------------------------------------------------------------
  if (bestScore < MATCH_THRESHOLD) {
    console.log(
      `[${ts()}] [Matcher] Best score ${bestScore} < threshold ${MATCH_THRESHOLD} — no match`,
    );
    repo.upsert({
      discogsReleaseId: discogs_release_id ?? null,
      artist, album,
      neteaseAlbumId:   null,
      neteaseAlbumName: null,
      confidence:       bestScore,
      deeplink:         null,
    });
    return { matched: false };
  }

  // -------------------------------------------------------------------------
  // STEP 7: Build deeplink & persist
  // -------------------------------------------------------------------------
  const deeplink = buildDeeplink(bestCandidate.id);

  console.log(
    `[${ts()}] [Matcher] ✓ Match: id=${bestCandidate.id} ` +
    `"${bestCandidate.name}" score=${bestScore} deeplink=${deeplink}`,
  );

  repo.upsert({
    discogsReleaseId: discogs_release_id ?? null,
    artist, album,
    neteaseAlbumId:   bestCandidate.id,
    neteaseAlbumName: bestCandidate.name,
    confidence:       bestScore,
    deeplink,
  });

  // -------------------------------------------------------------------------
  // STEP 8: Return result
  // -------------------------------------------------------------------------
  return {
    matched:            true,
    netease_album_id:   bestCandidate.id,
    netease_album_name: bestCandidate.name,
    confidence:         bestScore,
    deeplink,
    debug: {
      breakdown:     bestBreakdown,
      enriched_year: enrichedYear,
      track_count:   enrichedTrackCount,
    },
  };
}

module.exports = { matchAlbum, buildDeeplink };
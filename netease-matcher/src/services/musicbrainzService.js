'use strict';

/**
 * musicbrainzService.js
 *
 * Queries the MusicBrainz API to retrieve supplementary release metadata
 * (track count, canonical year, canonical artist) that improves confidence
 * scoring when comparing against NetEase candidates.
 *
 * MusicBrainz rate-limit: 1 request/second for anonymous; with a proper
 * User-Agent the limit is more generous but we still add a 1 s delay guard.
 *
 * Docs: https://musicbrainz.org/doc/MusicBrainz_API
 */

const axios       = require('axios');
const axiosRetry  = require('axios-retry').default;

const MUSICBRAINZ_BASE = 'https://musicbrainz.org/ws/2';

// Build the required User-Agent header per MusicBrainz policy:
//   ApplicationName/Version (contact)
function userAgent() {
  const app     = process.env.MUSICBRAINZ_APP_NAME    || 'netease-matcher';
  const version = process.env.MUSICBRAINZ_APP_VERSION || '1.0.0';
  const contact = process.env.MUSICBRAINZ_CONTACT     || 'contact@example.com';
  return `${app}/${version} ( ${contact} )`;
}

// Dedicated axios instance for MusicBrainz
const mbClient = axios.create({
  baseURL: MUSICBRAINZ_BASE,
  timeout: 8000,
  headers: {
    'User-Agent': userAgent(),
    Accept: 'application/json',
  },
});

// Retry on 503 / network errors (max 3 attempts, exponential back-off)
axiosRetry(mbClient, {
  retries: 3,
  retryDelay: axiosRetry.exponentialDelay,
  retryCondition: (err) =>
    axiosRetry.isNetworkOrIdempotentRequestError(err) ||
    err.response?.status === 503,
});

// Simple in-process request queue — MusicBrainz requires ≤ 1 req/s
let lastRequestTime = 0;
async function throttle() {
  const now  = Date.now();
  const wait = 1100 - (now - lastRequestTime); // 1.1 s gap to be safe
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  lastRequestTime = Date.now();
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Search MusicBrainz for a release by artist + album title.
 *
 * Returns the best-matching release or null if nothing useful is found.
 *
 * @param {string} artist
 * @param {string} album
 * @returns {Promise<{title:string, artist:string, year:number|null, trackCount:number|null}|null>}
 */
async function searchRelease(artist, album) {
  try {
    await throttle();

    // Lucene query syntax supported by MusicBrainz
    const query = `artist:"${artist}" AND release:"${album}"`;

    const { data } = await mbClient.get('/release/', {
      params: {
        query,
        limit: 5,
        fmt: 'json',
      },
    });

    const releases = data?.releases ?? [];
    if (releases.length === 0) return null;

    // Pick the release with the highest MusicBrainz score
    const best = releases.reduce((prev, curr) =>
      (curr.score || 0) > (prev.score || 0) ? curr : prev,
      releases[0],
    );

    const year = extractYear(best.date);
    const trackCount = best['track-count'] ?? extractTrackCount(best);

    return {
      title: best.title ?? '',
      artist: best['artist-credit']?.[0]?.name ?? artist,
      year,
      trackCount,
    };
  } catch (err) {
    // MusicBrainz failures are non-fatal — log and continue without
    console.warn(`[MusicBrainz] search failed for "${artist} - ${album}": ${err.message}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Extract a 4-digit year from a date string like "2013-05-17" or "2013".
 *
 * @param {string|null|undefined} dateStr
 * @returns {number|null}
 */
function extractYear(dateStr) {
  if (!dateStr) return null;
  const match = dateStr.match(/^(\d{4})/);
  return match ? parseInt(match[1], 10) : null;
}

/**
 * Attempt to sum track counts from the media array if track-count is missing.
 *
 * @param {object} release — raw MusicBrainz release object
 * @returns {number|null}
 */
function extractTrackCount(release) {
  const media = release.media ?? [];
  if (media.length === 0) return null;
  const total = media.reduce((sum, m) => sum + (m['track-count'] || 0), 0);
  return total > 0 ? total : null;
}

module.exports = { searchRelease };
'use strict';

/**
 * neteaseService.js
 *
 * Searches NetEase Cloud Music (网易云音乐) for albums matching a query string.
 *
 * Two search backends are supported (chosen via NETEASE_API_BASE_URL env var):
 *
 *   A) NeteaseCloudMusicApi proxy (recommended for production)
 *      Set NETEASE_API_BASE_URL=http://localhost:3001  (or your deployed URL)
 *      Endpoint: GET /cloudsearch?keywords=<q>&type=10&limit=20
 *      Project: https://github.com/Binaryify/NeteaseCloudMusicApi
 *
 *   B) Direct music.163.com legacy API (no extra server needed, best-effort)
 *      Used automatically when NETEASE_API_BASE_URL is not set.
 *      Endpoint: POST https://music.163.com/api/search/pc
 *
 * Rate limit: Bottleneck limiter — 5 requests/second max.
 */

const axios      = require('axios');
const axiosRetry = require('axios-retry').default;
const Bottleneck = require('bottleneck');

// ---------------------------------------------------------------------------
// Rate limiter — 5 req/s as specified
// ---------------------------------------------------------------------------
const limiter = new Bottleneck({
  maxConcurrent: 3,
  minTime: 200, // 200 ms between requests = 5 req/s
});

// ---------------------------------------------------------------------------
// Axios instance for the direct music.163.com API
// ---------------------------------------------------------------------------
const directClient = axios.create({
  baseURL: 'https://music.163.com',
  timeout: 10000,
  headers: {
    'Content-Type': 'application/x-www-form-urlencoded',
    Referer: 'https://music.163.com',
    Origin: 'https://music.163.com',
    'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ' +
      'AppleWebKit/537.36 (KHTML, like Gecko) ' +
      'Chrome/122.0.0.0 Safari/537.36',
    Cookie: 'appver=2.0.2; os=pc; MUSIC_A=;',
  },
});

axiosRetry(directClient, {
  retries: 2,
  retryDelay: axiosRetry.exponentialDelay,
  retryCondition: axiosRetry.isNetworkOrIdempotentRequestError,
});

// ---------------------------------------------------------------------------
// Axios instance for the NeteaseCloudMusicApi proxy
// ---------------------------------------------------------------------------
function makeProxyClient(baseURL) {
  const client = axios.create({ baseURL, timeout: 10000 });
  axiosRetry(client, {
    retries: 2,
    retryDelay: axiosRetry.exponentialDelay,
    retryCondition: axiosRetry.isNetworkOrIdempotentRequestError,
  });
  return client;
}

// ---------------------------------------------------------------------------
// Result normalisation
// ---------------------------------------------------------------------------

/**
 * @typedef {object} NeteaseAlbum
 * @property {number}      id
 * @property {string}      name
 * @property {string}      artist
 * @property {number|null} year
 * @property {number|null} trackCount
 */

/**
 * Parse a raw album object from either API backend into a NeteaseAlbum.
 *
 * @param {object} raw — raw album object from the API
 * @returns {NeteaseAlbum}
 */
function parseAlbum(raw) {
  // Artist name: may be under `artist.name` or `artists[0].name`
  let artist = '';
  if (raw.artist?.name) {
    artist = raw.artist.name;
  } else if (Array.isArray(raw.artists) && raw.artists.length > 0) {
    artist = raw.artists.map((a) => a.name).join(' / ');
  }

  // Year: publishTime is a Unix timestamp in milliseconds
  let year = null;
  if (raw.publishTime && raw.publishTime > 0) {
    year = new Date(raw.publishTime).getFullYear();
  }

  return {
    id:         raw.id,
    name:       raw.name ?? '',
    artist,
    year,
    trackCount: raw.size ?? null, // "size" = number of tracks in NE API
  };
}

// ---------------------------------------------------------------------------
// Backend A: NeteaseCloudMusicApi proxy
// ---------------------------------------------------------------------------

/**
 * Search via the NeteaseCloudMusicApi proxy server.
 *
 * @param {string} baseURL
 * @param {string} keywords
 * @returns {Promise<NeteaseAlbum[]>}
 */
async function searchViaProxy(baseURL, keywords) {
  const client = makeProxyClient(baseURL);
  const { data } = await client.get('/cloudsearch', {
    params: { keywords, type: 10, limit: 20 },
  });

  // Proxy response: { result: { albums: [...] } }
  const albums = data?.result?.albums ?? [];
  return albums.map(parseAlbum);
}

// ---------------------------------------------------------------------------
// Backend B: Direct music.163.com legacy API
// ---------------------------------------------------------------------------

/**
 * Search via direct POST to music.163.com/api/search/pc.
 * This endpoint accepts plain form-encoded parameters (no encryption needed).
 *
 * @param {string} keywords
 * @returns {Promise<NeteaseAlbum[]>}
 */
async function searchViaDirect(keywords) {
  const body = new URLSearchParams({
    s:      keywords,
    type:   '10',        // 10 = album search
    offset: '0',
    sub:    'false',
    limit:  '20',
  });

  const { data } = await directClient.post('/api/search/pc', body.toString());

  // Direct API response: { result: { albums: [...] } } or { code, result: { albums: [...] } }
  const albums = data?.result?.albums ?? [];
  return albums.map(parseAlbum);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Search NetEase Cloud Music for albums matching `keywords`.
 * Respects the 5 req/s rate limit via Bottleneck.
 *
 * @param {string} artist
 * @param {string} album
 * @returns {Promise<NeteaseAlbum[]>}  may be empty on failure
 */
async function searchAlbums(artist, album) {
  const keywords = `${artist} ${album}`.trim();
  const baseURL  = (process.env.NETEASE_API_BASE_URL || '').trim();

  return limiter.schedule(async () => {
    try {
      if (baseURL) {
        return await searchViaProxy(baseURL, keywords);
      } else {
        return await searchViaDirect(keywords);
      }
    } catch (err) {
      console.warn(
        `[NetEase] search failed for "${keywords}": ${err.message}` +
        (err.response ? ` (HTTP ${err.response.status})` : ''),
      );
      return [];
    }
  });
}

/**
 * Fetch full album details (including track list) from NetEase.
 * Used only if we need exact track counts for a specific album ID.
 *
 * @param {number} albumId
 * @returns {Promise<{trackCount:number|null}|null>}
 */
async function getAlbumDetail(albumId) {
  const baseURL = (process.env.NETEASE_API_BASE_URL || '').trim();

  return limiter.schedule(async () => {
    try {
      if (baseURL) {
        const client = makeProxyClient(baseURL);
        const { data } = await client.get('/album', { params: { id: albumId } });
        const songs = data?.songs ?? data?.album?.songs ?? [];
        return { trackCount: songs.length || null };
      } else {
        const { data } = await directClient.get(`/api/album/${albumId}`);
        const songs = data?.album?.songs ?? [];
        return { trackCount: songs.length || null };
      }
    } catch (err) {
      console.warn(`[NetEase] album detail failed for id=${albumId}: ${err.message}`);
      return null;
    }
  });
}

module.exports = { searchAlbums, getAlbumDetail };
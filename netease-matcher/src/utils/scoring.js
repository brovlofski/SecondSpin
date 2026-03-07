'use strict';

/**
 * scoring.js
 *
 * Implements the multi-signal confidence score used to decide whether a
 * NetEase album candidate is the correct match for a Discogs release.
 *
 * Final score formula (sum = 1.0):
 *   0.55 × title_similarity   — most important signal
 *   0.25 × artist_similarity  — second most important
 *   0.10 × track_count_score  — useful when track list is available
 *   0.10 × year_score         — year proximity bonus
 *
 * Both title and artist similarity use Jaro-Winkler distance, which
 * rewards shared prefixes and is more robust than plain Levenshtein for
 * proper names and album titles.
 */

// ---------------------------------------------------------------------------
// Jaro-Winkler implementation (pure JS, no external dependency)
// ---------------------------------------------------------------------------

/**
 * Jaro similarity between two strings.
 * Returns a value in [0, 1] where 1 = identical.
 *
 * @param {string} s1
 * @param {string} s2
 * @returns {number}
 */
function jaro(s1, s2) {
  if (s1 === s2) return 1;
  const len1 = s1.length;
  const len2 = s2.length;
  if (len1 === 0 || len2 === 0) return 0;

  // Match window: floor(max(len1,len2)/2) - 1
  const matchWindow = Math.floor(Math.max(len1, len2) / 2) - 1;
  if (matchWindow < 0) return 0;

  const s1Matches = new Array(len1).fill(false);
  const s2Matches = new Array(len2).fill(false);
  let matches = 0;
  let transpositions = 0;

  // Count matching characters
  for (let i = 0; i < len1; i++) {
    const start = Math.max(0, i - matchWindow);
    const end   = Math.min(i + matchWindow + 1, len2);
    for (let j = start; j < end; j++) {
      if (s2Matches[j] || s1[i] !== s2[j]) continue;
      s1Matches[i] = true;
      s2Matches[j] = true;
      matches++;
      break;
    }
  }

  if (matches === 0) return 0;

  // Count transpositions
  let k = 0;
  for (let i = 0; i < len1; i++) {
    if (!s1Matches[i]) continue;
    while (!s2Matches[k]) k++;
    if (s1[i] !== s2[k]) transpositions++;
    k++;
  }

  return (matches / len1 + matches / len2 + (matches - transpositions / 2) / matches) / 3;
}

/**
 * Jaro-Winkler similarity — gives a bonus for shared prefix (up to 4 chars).
 * p is the scaling factor (standard = 0.1; max 0.25).
 *
 * @param {string} s1 — normalized string
 * @param {string} s2 — normalized string
 * @param {number} [p=0.1]
 * @returns {number} similarity in [0, 1]
 */
function jaroWinkler(s1, s2, p = 0.1) {
  const j = jaro(s1, s2);
  // Common prefix length (at most 4)
  let prefixLen = 0;
  const maxPrefix = Math.min(4, Math.min(s1.length, s2.length));
  for (let i = 0; i < maxPrefix; i++) {
    if (s1[i] === s2[i]) prefixLen++;
    else break;
  }
  return j + prefixLen * p * (1 - j);
}

// ---------------------------------------------------------------------------
// Word-overlap (Jaccard) similarity
// Used as a secondary signal when title/artist is multi-word.
// ---------------------------------------------------------------------------

/**
 * Jaccard similarity on word sets.
 *
 * @param {string} a — space-separated words
 * @param {string} b — space-separated words
 * @returns {number} in [0, 1]
 */
function wordJaccard(a, b) {
  const sa = new Set(a.split(' ').filter(Boolean));
  const sb = new Set(b.split(' ').filter(Boolean));
  let inter = 0;
  for (const w of sa) { if (sb.has(w)) inter++; }
  const union = sa.size + sb.size - inter;
  return union === 0 ? 0 : inter / union;
}

// ---------------------------------------------------------------------------
// Individual sub-scores
// ---------------------------------------------------------------------------

/**
 * Title similarity: max(jaro-winkler, word-jaccard).
 * Using the max of both metrics handles both character-level similarities
 * (Jaro-Winkler) and set-based overlap (Jaccard) gracefully.
 *
 * @param {string} normTitle1 — already normalized
 * @param {string} normTitle2 — already normalized
 * @returns {number} in [0, 1]
 */
function titleSimilarity(normTitle1, normTitle2) {
  if (!normTitle1 || !normTitle2) return 0;
  if (normTitle1 === normTitle2) return 1;
  const jw = jaroWinkler(normTitle1, normTitle2);
  const jac = wordJaccard(normTitle1, normTitle2);
  return Math.max(jw, jac);
}

/**
 * Artist similarity: checks direct JW similarity + containment.
 *
 * "Daft Punk" vs "Daft Punk & Pharrell Williams" → high score via containment.
 *
 * @param {string} normArtist1 — already normalized
 * @param {string} normArtist2 — already normalized
 * @returns {number} in [0, 1]
 */
function artistSimilarity(normArtist1, normArtist2) {
  if (!normArtist1 || !normArtist2) return 0;
  if (normArtist1 === normArtist2) return 1;

  const direct = jaroWinkler(normArtist1, normArtist2);

  // Containment bonus: if the shorter artist name is contained in the longer one
  const [shorter, longer] = normArtist1.length <= normArtist2.length
    ? [normArtist1, normArtist2]
    : [normArtist2, normArtist1];

  const containsBonus = longer.includes(shorter) ? 0.95 : 0;

  return Math.max(direct, containsBonus);
}

/**
 * Track-count score.
 *
 * | difference | score |
 * |------------|-------|
 * | 0–1        | 1.0   |
 * | 2–3        | 0.5   |
 * | > 3        | 0.0   |
 *
 * Returns 0 if either value is absent/zero.
 *
 * @param {number|null} count1
 * @param {number|null} count2
 * @returns {number} in [0, 1]
 */
function trackCountScore(count1, count2) {
  if (!count1 || !count2 || count1 <= 0 || count2 <= 0) return 0;
  const diff = Math.abs(count1 - count2);
  if (diff <= 1) return 1;
  if (diff <= 3) return 0.5;
  return 0;
}

/**
 * Year proximity score.
 *
 * | difference | score |
 * |------------|-------|
 * | 0–1        | 1.0   |
 * | 2–3        | 0.5   |
 * | > 3        | 0.0   |
 *
 * Returns 0 if either year is absent/zero.
 *
 * @param {number|null} year1
 * @param {number|null} year2
 * @returns {number} in [0, 1]
 */
function yearScore(year1, year2) {
  if (!year1 || !year2 || year1 <= 0 || year2 <= 0) return 0;
  const diff = Math.abs(year1 - year2);
  if (diff <= 1) return 1;
  if (diff <= 3) return 0.5;
  return 0;
}

// ---------------------------------------------------------------------------
// Composite scorer
// ---------------------------------------------------------------------------

/**
 * Compute the composite confidence score for a NetEase candidate vs. a
 * Discogs release. All string inputs must already be normalized.
 *
 * @param {object} candidate
 * @param {string} candidate.normTitle   — normalized NetEase album title
 * @param {string} candidate.normArtist  — normalized NetEase artist name
 * @param {number|null} candidate.year   — NetEase release year (can be null)
 * @param {number|null} candidate.trackCount — NetEase track count (can be null)
 *
 * @param {object} release
 * @param {string} release.normTitle     — normalized Discogs title
 * @param {string} release.normArtist    — normalized Discogs artist
 * @param {number|null} release.year     — Discogs release year (can be null)
 * @param {number|null} release.trackCount — from tracklist or MusicBrainz (can be null)
 *
 * @returns {{ score: number, breakdown: object }}
 */
function computeScore(candidate, release) {
  const titleSim  = titleSimilarity(candidate.normTitle,  release.normTitle);
  const artistSim = artistSimilarity(candidate.normArtist, release.normArtist);
  const trackSc   = trackCountScore(candidate.trackCount, release.trackCount);
  const yearSc    = yearScore(candidate.year, release.year);

  const score =
    0.55 * titleSim +
    0.25 * artistSim +
    0.10 * trackSc  +
    0.10 * yearSc;

  return {
    score: Math.round(score * 1000) / 1000,  // 3 d.p.
    breakdown: { titleSim, artistSim, trackSc, yearSc },
  };
}

module.exports = {
  jaroWinkler,
  wordJaccard,
  titleSimilarity,
  artistSimilarity,
  trackCountScore,
  yearScore,
  computeScore,
};
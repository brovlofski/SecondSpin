'use strict';

/**
 * normalize.js
 * 
 * String normalization utilities for album/artist matching.
 * Strips edition suffixes, punctuation, and normalizes Unicode
 * so that "Random Access Memories (Deluxe Edition)" and
 * "Random Access Memories" produce the same normalized form.
 */

// Suffixes that indicate variant editions — these should be stripped
// before comparing titles so that the original and a deluxe edition
// still produce a high similarity score.
const EDITION_PATTERNS = [
  /\(?\s*remastered(?:\s+\d{4})?\s*\)?/gi,
  /\(?\s*\d{4}\s+remaster(?:ed)?\s*\)?/gi,
  /\(?\s*deluxe(?:\s+edition)?\s*\)?/gi,
  /\(?\s*expanded(?:\s+edition)?\s*\)?/gi,
  /\(?\s*anniversary(?:\s+edition)?\s*\)?/gi,
  /\(?\s*\d+(?:th|st|nd|rd)\s+anniversary(?:\s+edition)?\s*\)?/gi,
  /\(?\s*super\s+deluxe(?:\s+edition)?\s*\)?/gi,
  /\(?\s*special(?:\s+edition)?\s*\)?/gi,
  /\(?\s*limited(?:\s+edition)?\s*\)?/gi,
  /\(?\s*collector['']?s(?:\s+edition)?\s*\)?/gi,
  /\(?\s*bonus\s+tracks?\s*\)?/gi,
  /\(?\s*bonus\s+disc\s*\)?/gi,
  /\(?\s*\[.*?\]\s*/gi,          // strip anything in square brackets
];

/**
 * Normalize a title for comparison:
 *   1. Strip edition/variant suffixes
 *   2. Lowercase
 *   3. Replace punctuation with spaces (keep alphanumeric + spaces)
 *   4. Collapse whitespace
 *
 * @param {string} str
 * @returns {string}
 */
function normalizeTitle(str) {
  if (!str) return '';
  let s = str;
  for (const pattern of EDITION_PATTERNS) {
    s = s.replace(pattern, ' ');
  }
  return s
    .toLowerCase()
    .normalize('NFD')                           // decompose accented chars
    .replace(/[\u0300-\u036f]/g, '')            // strip combining diacritics
    .replace(/[^a-z0-9\s]/g, ' ')              // replace punctuation with space
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Normalize an artist name for comparison:
 *   - Lowercase, strip punctuation, collapse whitespace
 *   - Does NOT strip edition patterns (those are title-specific)
 *
 * @param {string} str
 * @returns {string}
 */
function normalizeArtist(str) {
  if (!str) return '';
  return str
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Tokenize a normalized string into an array of words.
 * Useful for word-overlap scoring.
 *
 * @param {string} str — already normalized
 * @returns {string[]}
 */
function tokenize(str) {
  return str.split(' ').filter(Boolean);
}

/**
 * Return the set of words in a normalized string.
 *
 * @param {string} str — already normalized
 * @returns {Set<string>}
 */
function wordSet(str) {
  return new Set(tokenize(str));
}

module.exports = { normalizeTitle, normalizeArtist, tokenize, wordSet };
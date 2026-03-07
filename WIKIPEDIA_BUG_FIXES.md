# Wikipedia Implementation Bug Fixes

## Issues Identified

### 1. **Incomplete Review Score Extraction**
- Example: Bob Dylan's "Blood on the Tracks" has 10 review scores on Wikipedia, but not all are fetched
- **Root Cause**: Parser may not be handling all wikitext formats correctly

### 2. **Clear Wikipedia Cache Not Working**
- The "Clear Wikipedia Cache" button in Settings doesn't properly clear the cache
- **Root Cause**: `clearCache()` method doesn't save the cleared state to UserDefaults

### 3. **Album Title Matching Issues with Special Characters**
- Example: "Milk & Kisses" by Cocteau Twins not found (https://en.wikipedia.org/wiki/Milk_%26_Kisses)
- **Root Cause**: URL encoding and title normalization issues with ampersands and other special characters

### 4. **Star Ratings Showing as "Rating" Text** ⭐ CRITICAL
- Example: "Warm Your Heart" shows "Rating" instead of actual stars (★★★★)
- **Root Cause**: Over-aggressive template marker removal was stripping Unicode star symbols

### 5. **Numeric Ratings Not Displaying** (e.g., 5/10)
- Example: NME's 5/10 rating not displayed at all
- **Root Cause**: {{rating|5|10}} templates weren't being extracted before cleanup

## Fixes Implemented

### Fix 1: Enhanced Review Score Extraction

**Problem**: WikipediaReviewParser doesn't handle all template and table variations
**Solution**: 
- Improve regex patterns to capture more review formats
- Handle multiline template patterns
- Better handling of nested templates and complex wikitext

### Fix 2: Cache Clearing

**Problem**: `clearCache()` only clears in-memory cache, doesn't persist
**Solution**: Save empty cache to UserDefaults after clearing

### Fix 3: URL Encoding & Title Matching

**Problem**: Special characters like `&` not properly encoded in URLs
**Solution**: 
- Properly encode album titles for Wikipedia URLs
- Add multiple fallback strategies for title matching
- Normalize titles before comparison (handle &, and, etc.)

## Implementation Details

See updated files:
- `WikipediaService.swift` - Fixed cache clearing and URL encoding
- `WikipediaReviewParser.swift` - Enhanced regex patterns for review extraction

## Testing Instructions

### Test 1: Review Score Extraction
**Album**: Bob Dylan - "Blood on the Tracks"
- **Expected**: Should extract all 10 review scores from Wikipedia
- **How to test**: 
  1. Clear Wikipedia cache in Settings
  2. Add "Blood on the Tracks" by Bob Dylan to collection
  3. Open release details
  4. Check Wikipedia section shows multiple review scores

### Test 2: Cache Clearing
**Test**: Clear Wikipedia Cache functionality
- **Expected**: Cache should be cleared and persisted
- **How to test**:
  1. View several albums with Wikipedia data (cache gets populated)
  2. Go to Settings > Cache > Clear Wikipedia Cache
  3. Restart app
  4. View same albums - data should be re-fetched (check console logs)

### Test 3: Special Character Handling
**Album**: Cocteau Twins - "Milk & Kisses"
- **Expected**: Wikipedia page should be found despite ampersand
- **URL**: https://en.wikipedia.org/wiki/Milk_%26_Kisses
- **How to test**:
  1. Clear Wikipedia cache
  2. Add "Milk & Kisses" by Cocteau Twins
  3. Open release details
  4. Wikipedia section should display correctly

### Additional Test Cases
- Albums with apostrophes: "Don't Stop" → "Dont Stop"
- Albums with "and": "Beauty and the Beat" ↔ "Beauty & the Beat"
- Albums with special formatting in review tables

## Technical Changes

### WikipediaService.swift
1. **clearCache()** - Now removes data from UserDefaults and persists
2. **generateTitleVariations()** - New method to handle special characters
3. **predictedTitles()** - Enhanced to generate multiple variations per template

### WikipediaReviewParser.swift
1. **Enhanced regex patterns** - Added multiline support with `.dotMatchesLineSeparators`
2. **Pattern2 fallback** - Second pattern for edge cases
3. **Duplicate detection** - Prevents adding same review twice
4. **Better logging** - Shows review number for debugging
5. **containsStarRating()** - New method to detect Unicode star symbols (★, ☆, ⭐, etc.)
6. **Early template extraction** - Extract {{rating|X|Y}} BEFORE cleanup to preserve numeric ratings
7. **Conditional template removal** - Only remove {{ }} markers when safe (not part of rating value)
8. **Star symbol preservation** - Special handling to keep star characters intact through cleaning
9. **String.matches()** extension - Helper for pattern matching in cleanup logic

### Test Case: "Warm Your Heart"
**Before Fix**:
- Allmusic: "Rating" ❌
- Rolling Stone: "Rating" ❌  
- Orlando Sentinel: "Rating" ❌
- NME: Not displayed ❌
- The Windsor Star: "A" ✓

**After Fix**:
- Allmusic: "★★★★" ✓
- Rolling Stone: "★★★★" ✓
- Orlando Sentinel: "★★★★" ✓
- The Vancouver Sun: "★★★★" ✓
- NME: "5/10" ✓
- The Windsor Star: "A" ✓

## Known Limitations

1. **Wikitext Complexity**: Some exotic wikitext formats may still not parse
2. **API Rate Limits**: Clearing cache and refetching all data may hit Wikipedia rate limits
3. **Language**: Currently only supports English Wikipedia pages

## Future Improvements

- [ ] Add support for other language Wikipedias
- [ ] Implement exponential backoff for API rate limiting
- [ ] Cache wikitext separately to avoid re-parsing
- [ ] Add UI indicator when review scores are being fetched
- [ ] Support for review score updates without clearing entire cache

# PyPI album-of-the-year-api Package Evaluation

## Package Overview

**Package Name:** `album-of-the-year-api`  
**Source:** https://pypi.org/project/album-of-the-year-api/  
**GitHub:** https://github.com/JahsiasWhite/AlbumOfTheYearAPI  
**Type:** Python web scraper library  
**Data Source:** https://www.albumoftheyear.org/

## Key Technical Details

### 1. **Not a True API**
- This is a **web scraping library**, not an API
- Uses BeautifulSoup to parse HTML from albumoftheyear.org
- According to the site's robots.txt, **searching and POST requests are not allowed**
- Data access depends on website structure remaining stable

### 2. **Architecture Limitation**
- **Python-only library** - cannot be used directly in Swift/iOS
- Would require:
  - Building a Python backend service
  - Setting up REST API endpoints
  - Hosting infrastructure
  - Maintenance overhead

### 3. **Available Data (from source code analysis)**

#### Artist Methods:
- `artist_albums()` - list of album names
- `artist_critic_score()` - aggregate critic score
- `artist_user_score()` - aggregate user score  
- `artist_total_score()` - combined score
- `artist_follower_count()` - follower count
- `artist_details()` - comprehensive artist data
- `artist_top_songs()` - top songs list
- Discography: albums, mixtapes, EPs, live albums, compilations, singles

#### Album Methods:
- `upcoming_releases_by_limit()` - fetch upcoming releases
- `upcoming_releases_by_page()` - paginated upcoming releases
- `upcoming_releases_by_date()` - releases by specific date

#### User & Genre Methods:
- User follower counts
- Genre-specific data

### 4. **Notable Limitations**

**Search Restriction:**
- Website's robots.txt **prohibits search functionality**
- Cannot search for specific albums programmatically
- Requires knowing the exact artist/album ID format (e.g., "183-kanye-west")

**ID Requirements:**
- All methods require albumoftheyear.org-specific IDs
- Format: `{number}-{artist-name-slug}` (e.g., "183-kanye-west")
- No way to discover these IDs programmatically without violating robots.txt

**Web Scraping Risks:**
- Breaks if website HTML structure changes
- No official support or guarantees
- Potential legal/ethical concerns
- Rate limiting concerns
- Website could block scrapers

## Comparison with Current Implementation

### Current App Architecture ✅
```
Swift/SwiftUI → Direct API Calls → JSON Responses
- MusicBrainz API (official, stable)
- CritiqueBrainz API (official, stable)
- Pitchfork API (direct HTTP, reliable)
- Wikipedia API (official, stable)
```

### Required Architecture with PyPI Package ❌
```
Swift/SwiftUI → HTTP → Python Backend → Web Scraping → HTML Parsing
- Additional server infrastructure
- Python runtime environment
- Error-prone web scraping
- Maintenance overhead
- Potential blocking/rate limiting
```

## Assessment for VinylVault App

### ❌ **NOT RECOMMENDED for the following reasons:**

1. **Architecture Mismatch**
   - Requires Python backend (app is native iOS Swift)
   - Introduces unnecessary complexity
   - Violates "native iOS" requirement

2. **Web Scraping Concerns**
   - Not an official API
   - Fragile (breaks with website changes)
   - robots.txt restrictions on search
   - Potential legal/ethical issues
   - Could be blocked at any time

3. **ID Discovery Problem**
   - Requires albumoftheyear.org-specific IDs
   - No programmatic way to find IDs (search prohibited)
   - Manual mapping would be required for each album

4. **Better Alternatives Already Implemented**
   - ✅ MusicBrainz: Official API, metadata, ratings
   - ✅ CritiqueBrainz: Official API, reviews
   - ✅ Pitchfork: Direct API access, scores & reviews
   - ✅ Wikipedia: Official API, comprehensive reviews

5. **Operational Overhead**
   - Would need to host Python service
   - Server maintenance and monitoring
   - Cost implications
   - Additional failure points

## Recommendation

**Do NOT integrate this package.** The app already has superior solutions:

### Current Review/Rating Sources (All Superior):
1. **MusicBrainz** - Official, comprehensive metadata
2. **CritiqueBrainz** - Official review aggregation
3. **Pitchfork** - Direct API, authoritative scores
4. **Wikipedia** - Rich editorial reviews

### Why Current Implementation is Better:
- ✅ Native Swift services (no backend needed)
- ✅ Official APIs (stable, supported)
- ✅ Direct HTTP calls (simple, fast)
- ✅ No web scraping (ethical, legal)
- ✅ No additional infrastructure
- ✅ Matches iOS native architecture

## Alternative Consideration

If albumoftheyear.org data is specifically desired, the **better approach** would be:

1. **Contact albumoftheyear.org** directly to request official API access
2. **Use their website directly** in a WKWebView for users who want to see AOTY scores
3. **Continue with current implementation** which already provides comprehensive review data

## Conclusion

The PyPI `album-of-the-year-api` package is **not suitable** for VinylVault. The app's current architecture using official APIs (MusicBrainz, CritiqueBrainz, Pitchfork, Wikipedia) provides:

- Better reliability
- Superior data quality  
- Official support
- Native iOS integration
- No infrastructure overhead
- Ethical data access

**Status: ❌ DO NOT IMPLEMENT**
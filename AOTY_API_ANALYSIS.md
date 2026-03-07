# AOTY API Analysis & Integration

## API Overview

**Base URL**: `https://albums-aoty-api-production.up.railway.app`

This API scrapes Pitchfork's year-end "Best Albums" lists and provides ranking data.

## Available Endpoints

### 1. Get Albums by Year
```
GET /{year}?limit={number}
```

**Parameters:**
- `year` (path): Year (e.g., 2023, 2022, 2016)
- `limit` (query, optional): Limit results (default: 50)

**Example:**
```bash
curl "https://albums-aoty-api-production.up.railway.app/2023?limit=5"
```

**Response:**
```json
[
  {
    "artist": "SZA",
    "album": "SOS",
    "rank": 1,
    "album-cover": "https://media.pitchfork.com/photos/..."
  }
]
```

### 2. Get All Years for an Artist
```
GET /all/{artist}
```

**Parameters:**
- `artist` (path): Exact artist name

**Example:**
```bash
curl "https://albums-aoty-api-production.up.railway.app/all/Radiohead"
```

**Response:**
```json
{
  "2016": {
    "artist": "Radiohead",
    "album": "A Moon Shaped Pool",
    "rank": 10,
    "album-cover": "https://media.pitchfork.com/photos/..."
  }
}
```

### 3. Get All Data
```
GET /all
```

Returns complete dataset of all years and albums.

## Limitations for Review Integration

### ❌ **Not Suitable for Primary Review Source**

1. **No Review Scores**: API only provides:
   - Artist name
   - Album title
   - Year-end ranking
   - Album cover URL
   
2. **No Review Text**: No actual review content or scores

3. **Limited Coverage**: Only albums that made Pitchfork's year-end "Best of" lists

4. **Year-End Lists Only**: Not comprehensive album reviews

5. **Exact Match Required**: Artist name must match exactly (case-sensitive)

## Potential Use Cases

### ✅ **Badge System**
Display a "Pitchfork Best of [Year] #[Rank]" badge for albums that made year-end lists:

```swift
if let ranking = aotyResponse.rank {
    // Show: "🏆 Pitchfork Best of 2023 #1"
}
```

### ✅ **Discovery Feature**
"Top Albums from Your Collection Years" - show what other albums from the same year were highly rated

### ✅ **Collection Highlights**
Filter/sort collection by "Albums that made Pitchfork year-end lists"

## Recommended Approach

**Keep Current Wikipedia Integration** for primary review data, and **optionally add AOTY API** for:
- Prestige badges (year-end list rankings)
- Discovery features
- Collection statistics

## Integration Decision

Given the API's limitations, I recommend:

1. **Primary Reviews**: Continue using Wikipedia (already implemented)
2. **Secondary Data**: Optionally add AOTY for "year-end list" badges
3. **Future**: Consider adding proper review APIs like:
   - Metacritic API (if available)
   - MusicBrainz ratings (already using MusicBrainz)
   - Rate Your Music API

## Sample Integration Code

If you want to add the badge feature, I can create:
- `AOTYService.swift` - Fetch year-end list data
- Badge UI component for ReleaseDetailView
- Collection filtering by "year-end list albums"

Would you like me to implement any of these features?
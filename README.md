# VinylVault - iOS Vinyl Record Collection Manager

A modern iOS app built with Swift and SwiftUI for managing your personal vinyl record collection.

## Features

### Core Features

- **Album of the Day**: Randomly featured album from your collection, refreshed daily
- **Barcode Scanning**: Use your camera to quickly add records by scanning barcodes
- **Manual Search**: Search Discogs database by artist and album title
- **Collection Management**: View your collection in grid or list layout
- **Multiple Copies**: Track multiple copies of the same release
- **Custom Lists**: Create and manage custom album lists (Favorites, Wishlist, etc.)
- **Rich Details**: View comprehensive album information including tracklist, genres, and Wikipedia descriptions
- **Streaming Links**: Quick access to Spotify and Apple Music for listening
- **Search**: Fast local search across your entire collection

### Technical Features

- **SwiftUI + MVVM Architecture**
- **SwiftData**: Local persistence with iOS 17+
- **Async/Await**: Modern networking with async/await
- **Image Caching**: Efficient image loading and caching
- **Light/Dark Mode**: Full support for system appearance
- **Native iOS Design**: San Francisco font, system components

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- Active internet connection for Discogs and Wikipedia APIs

## Project Structure

```
VinylVault/
├── App/
│   └── VinylVaultApp.swift          # App entry point
├── Models/
│   ├── Release.swift                # Release data model
│   ├── Copy.swift                   # Copy data model
│   └── RecordList.swift             # List data model
├── Services/
│   ├── DiscogsService.swift         # Discogs API integration
│   ├── WikipediaService.swift       # Wikipedia API integration
│   └── StreamingLinkService.swift   # Streaming link generation
├── Views/
│   ├── ContentView.swift            # Main tab navigation
│   ├── HomeView.swift               # Album of the Day
│   ├── CollectionView.swift         # Collection grid/list
│   ├── ListsView.swift              # Custom lists
│   ├── SearchView.swift             # Collection search
│   ├── AddRecordView.swift          # Add record entry point
│   ├── BarcodeScannerView.swift     # Barcode scanner
│   ├── ManualSearchView.swift       # Manual search
│   ├── SearchResultsView.swift      # Search results
│   ├── ReleaseDetailView.swift      # Release details
│   ├── AddCopyView.swift            # Add copy
│   ├── EditCopyView.swift           # Edit copy
│   ├── ListDetailView.swift         # List detail
│   └── [Supporting Views]
├── Utilities/
│   └── ImageCache.swift             # Image caching
└── Resources/
    └── Assets.xcassets              # App assets
```

## API Integration

### Discogs API

The app uses the Discogs API for album metadata:

- **Token**: Pre-configured with provided token
- **Endpoints**:
  - `/database/search` - Search by barcode or artist/title
  - `/releases/{id}` - Get release details
- **Rate Limiting**: Handled with proper error messages

### Wikipedia API

Wikipedia integration for album descriptions:

- **Endpoint**: `/w/api.php`
- **Fallback Logic**: Tries album + artist, then album only
- **Graceful Degradation**: Hides section if not found

## Building the Project

1. Open `VinylVault.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run (⌘R)

## Usage

### Adding Records

1. Tap the floating "+" button
2. Choose "Scan Barcode" or "Search Manually"
3. For barcode: Point camera at barcode
4. For manual: Enter artist and album title
5. Select from results

### Managing Copies

- Tap on an album to view details
- Each copy can have:
  - Purchase price
  - Condition (Mint, Near Mint, etc.)
  - Personal notes
  - Date added

### Creating Lists

1. Go to Lists tab
2. Tap "+" to create a new list
3. Add albums from your collection
4. Reorder or remove albums as needed

### Searching

- Use the Search tab to find albums
- Filter by artist, title, label, or genre
- Results update in real-time

## Data Models

### Release

- Discogs ID (unique)
- Title, Artist, Year, Label
- Cover images (full and thumbnail)
- Genres, Styles, Format
- Tracklist
- Barcode (optional)
- Date added
- Relationship to Copies and Lists

### Copy

- Purchase price (optional)
- Condition
- Notes
- Date added
- Belongs to a Release

### RecordList

- Name, Description
- Order index for sorting
- Many-to-many relationship with Releases

## Design Guidelines

- **Typography**: San Francisco system font throughout
- **Colors**: Native iOS colors with accent color support
- **Spacing**: Consistent 8pt grid system
- **Shadows**: Subtle shadows for depth
- **Animations**: Smooth transitions and interactions
- **Accessibility**: Full VoiceOver support

## Future Enhancements (Optional)

- iCloud sync across devices
- Export collection (CSV/JSON)
- Discogs marketplace integration
- Collection value estimation
- Barcode generation for custom records
- Collection statistics and insights
- Sharing lists with other users

## Architecture Notes

### MVVM Pattern

- **Models**: SwiftData models (Release, Copy, RecordList)
- **Views**: SwiftUI views with minimal logic
- **ViewModels**: ObservableObject classes for business logic

### Service Layer

Modular services for external integrations:
- `DiscogsService`: API calls and data transformation
- `WikipediaService`: Article fetching and parsing
- `StreamingLinkService`: URL generation for streaming platforms

### Data Persistence

- SwiftData for local storage
- Automatic schema migration
- Cascade delete rules for data integrity

## Camera Permissions

The app requires camera access for barcode scanning. The permission request includes a clear explanation of why camera access is needed.

## Error Handling

- Network errors: User-friendly error messages
- No results: Helpful suggestions
- Rate limiting: Retry prompts
- Offline mode: Graceful degradation

## License

This project is for personal use. Discogs API usage is subject to Discogs Terms of Service.

## Credits

- **Discogs API**: Album metadata and images
- **Wikipedia API**: Album descriptions and context
- **SF Symbols**: Icons throughout the app
- **SwiftUI**: Modern declarative UI framework
- **SwiftData**: Persistent data storage

---

Built with ❤️ using Swift and SwiftUI
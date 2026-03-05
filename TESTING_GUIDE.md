# VinylVault Testing Guide

## Prerequisites

### System Requirements
- **macOS**: Monterey (12.0) or later
- **Xcode**: 15.0 or later
- **iOS Device/Simulator**: iOS 17.0 or later

### Installation
1. Install Xcode from the Mac App Store (if not already installed)
2. Open Terminal and navigate to the project:
   ```bash
   cd /Users/I074544/Documents/Git/colorlines-game/VinylVault
   ```

## Testing Methods

### Method 1: iOS Simulator (Recommended for Quick Testing)

#### Step 1: Open the Project
```bash
open VinylVault.xcodeproj
```

#### Step 2: Select Simulator
In Xcode:
1. At the top of the window, click the device selector (next to the play button)
2. Choose any iPhone simulator (e.g., "iPhone 15 Pro")
3. iOS 17.0+ is required

#### Step 3: Build and Run
1. Press `⌘R` or click the Play button ▶️
2. Wait for the build to complete (first build may take 1-2 minutes)
3. The simulator will launch automatically with the app

#### Step 4: Test Features

**Note about Camera/Barcode in Simulator:**
- ⚠️ The barcode scanner will NOT work in the simulator (camera unavailable)
- Use "Search by Artist/Title" instead for testing

### Method 2: Physical iPhone (Full Feature Testing)

#### Requirements
- iPhone with iOS 17.0+
- Lightning/USB-C cable
- Developer mode enabled on iPhone

#### Setup Steps

1. **Enable Developer Mode on iPhone**:
   - Settings → Privacy & Security → Developer Mode → Toggle ON
   - Restart iPhone when prompted

2. **Connect iPhone to Mac**:
   - Connect via cable
   - Trust the computer when prompted on iPhone
   - Trust the device in Xcode when prompted

3. **Select Your iPhone**:
   - In Xcode device selector, choose your connected iPhone
   - Format: "Your Name's iPhone"

4. **Configure Code Signing** (first time only):
   - Click the project name in the left sidebar
   - Select the "VinylVault" target
   - Go to "Signing & Capabilities" tab
   - Select your Apple ID under "Team"
   - Xcode will automatically configure signing

5. **Build and Run**:
   - Press `⌘R`
   - The app will install and launch on your iPhone

6. **Grant Permissions**:
   - When prompted, allow camera access (required for barcode scanning)

## Feature Testing Checklist

### 1. Home Screen (Album of the Day)
- [ ] Launch app, should see "Album of the Day" section
- [ ] Initially shows "No albums in collection" message
- [ ] After adding albums, a random album appears daily
- [ ] Wikipedia section loads (if available)
- [ ] Tap "Read More" to expand full Wikipedia article

### 2. Adding Records

#### Via Manual Search (Works in Simulator)
1. Tap the **+** button (center bottom)
2. Select **"Search by Artist/Title"**
3. Test searches:
   - Artist: "Pink Floyd" | Album: "Dark Side of the Moon"
   - Artist: "The Beatles" | Album: "Abbey Road"
   - Artist: "Miles Davis" | Album: "Kind of Blue"
4. Results should appear with cover art, title, year
5. Tap a result → Review details → Tap "Add to Collection"
6. Enter optional purchase price and notes
7. Tap "Add Copy"

#### Via Barcode (Physical Device Only)
1. Tap the **+** button
2. Select **"Scan Barcode"**
3. Allow camera access if prompted
4. Point camera at vinyl barcode (EAN/UPC)
5. Example barcodes to test:
   - `0602537347452` - Random Access Memories (Daft Punk)
   - `0602557439458` - The Dark Side of the Moon (Pink Floyd)
6. App should auto-detect and show results

### 3. My Collection Screen

#### Grid View (Default)
- [ ] Tap "My Collection" tab
- [ ] See albums in 2-column grid
- [ ] Album covers load and display
- [ ] Tap an album → Opens detail view

#### List View
- [ ] Tap "List" in segmented control (top)
- [ ] See albums in list format with thumbnails
- [ ] Scroll through list

#### Sorting
- [ ] Tap sort button (top right)
- [ ] Try sorting by:
  - Artist (A-Z)
  - Title (A-Z)
  - Year (newest first)
  - Date Added (most recent)

#### Filtering
- [ ] Use search bar to filter by title/artist
- [ ] Tap filter button to filter by genre/format

#### Multiple Copies
- [ ] Add same album twice (use "Add to Collection" again)
- [ ] Album shows stacked covers with badge count
- [ ] Tap album → See list of all copies
- [ ] Each copy shows price, notes, date

### 4. Release Detail Screen
- [ ] Tap any album to open details
- [ ] Verify all sections load:
  - Cover image (large)
  - Title, artist, year, label
  - Genre/style tags
  - Tracklist (numbered)
  - Wikipedia section (may not exist for all albums)
- [ ] Test action buttons:
  - "Edit Copy" → Modify price/notes
  - "Remove from Collection" → Deletes album
  - Streaming links open in browser/apps

### 5. Lists Feature
- [ ] Tap "Lists" tab
- [ ] Tap "+" to create new list
- [ ] Enter name: "Favorites"
- [ ] Tap "Create"
- [ ] Tap list to open it
- [ ] Tap "+" to add albums
- [ ] Select multiple albums → Tap "Add"
- [ ] Albums appear in list
- [ ] Long press to reorder
- [ ] Swipe left to remove album
- [ ] Test list management:
  - Edit list name
  - Delete list

### 6. Search Tab
- [ ] Tap "Search" tab
- [ ] Use search bar to find albums
- [ ] Test searching by:
  - Artist name
  - Album title
  - Label name
  - Genre
- [ ] Use scope selector to filter:
  - All
  - Artist
  - Title
  - Label
  - Genre
- [ ] Results update in real-time

### 7. Visual & UI Testing

#### Light/Dark Mode
1. Open Control Center on iPhone/Simulator
2. Toggle Light/Dark mode
3. Verify app adapts properly:
   - Background colors change
   - Text remains readable
   - Album covers display correctly

#### Animations
- [ ] Grid ↔ List transition is smooth
- [ ] Tab switching animates properly
- [ ] Album covers fade in when loading
- [ ] Navigation transitions are smooth

#### Responsive Layout
- [ ] Rotate device to landscape
- [ ] UI adapts properly
- [ ] Grid adjusts column count if needed

### 8. Error Handling

#### Network Errors
1. Turn on Airplane Mode
2. Try to add a record
3. Should see error message: "Network unavailable"
4. Turn off Airplane Mode

#### Invalid Searches
- [ ] Search for nonsense: "ZZZZZZ"
- [ ] Should show "No results found"

#### Duplicate Detection
- [ ] Try adding same album twice
- [ ] Should increment copy count, not create duplicate release

### 9. Data Persistence
1. Add several albums to collection
2. Create a list with albums
3. Close app completely (swipe up in app switcher)
4. Reopen app
5. Verify:
   - [ ] Collection preserved
   - [ ] Lists preserved
   - [ ] Album of the Day persists until midnight

## Common Issues & Solutions

### Issue: "Untrusted Developer"
**Solution**: Settings → General → VPN & Device Management → Trust developer

### Issue: "Failed to prepare device for development"
**Solution**: 
1. Disconnect iPhone
2. Xcode → Window → Devices and Simulators
3. Remove device, reconnect, re-add

### Issue: Build Errors
**Solution**:
1. Clean build folder: `⌘⇧K`
2. Rebuild: `⌘B`

### Issue: Simulator Slow
**Solution**:
1. Use newer simulator (iPhone 15 Pro)
2. Increase simulator memory in Xcode preferences

### Issue: Barcode Not Scanning
**Solution**:
- Ensure adequate lighting
- Hold camera 6-12 inches from barcode
- Try different barcodes
- Verify camera permission granted

### Issue: Images Not Loading
**Solution**:
- Check internet connection
- Wait a few seconds for cache to populate
- Some albums may not have cover art in Discogs

## Performance Testing

### Test Large Collections
1. Add 50+ albums to collection
2. Verify:
   - [ ] Scrolling remains smooth
   - [ ] Search is fast
   - [ ] Grid/list switching is responsive
   - [ ] Memory usage is reasonable

### Test Image Caching
1. Add albums, scroll through collection
2. Close and reopen app
3. Images should load faster (from cache)

## API Testing

### Discogs API
- **Token included**: `ChNuGIHFtQvJKLkvcQQCEgcdDSVfXvKcVrxQASKO`
- **Rate limit**: 60 requests/minute (with token)
- Test by adding multiple albums quickly

### Wikipedia API
- Some albums have Wikipedia pages, some don't
- Test with popular albums (Pink Floyd, Beatles) for best results

## Recommended Test Workflow

### Quick Test (10 minutes)
1. Open in simulator
2. Add 3-4 albums via manual search
3. Switch between grid/list views
4. Test sorting
5. Create one list
6. Test search tab

### Full Test (30 minutes)
1. Test on physical device
2. Test barcode scanning
3. Add 10+ albums
4. Test all features above
5. Test light/dark mode
6. Test error scenarios
7. Verify data persistence

### Production Readiness (1 hour)
1. Complete full test workflow
2. Test with 50+ albums
3. Stress test APIs
4. Test on multiple devices
5. Test various network conditions
6. Verify all edge cases

## Debugging

### View Logs
In Xcode:
1. Open Debug Area: `⌘⇧Y`
2. View console output
3. Look for API responses, errors

### Inspect SwiftData
1. Add breakpoints in model files
2. Check database state
3. Verify relationships (Release ↔ Copy ↔ RecordList)

## Next Steps After Testing

### Found Bugs?
Document with:
- Device/simulator used
- iOS version
- Steps to reproduce
- Expected vs actual behavior

### App Works Great?
- Consider submitting to App Store
- Add more features from future-proofing list
- Share with friends who collect vinyl!

---

**Happy Testing! 🎵**

For questions or issues, refer to:
- `README.md` - General documentation
- `PROJECT_SUMMARY.md` - Technical details
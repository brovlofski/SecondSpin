# MusicBrainz Integration Setup Guide

## ✅ Files Created

The following files have been created and need to be added to your Xcode project:

### Models
- `VinylVault/Models/MusicBrainzModels.swift`

### Services
- `VinylVault/Services/MusicBrainzService.swift`
- `VinylVault/Services/CritiqueBrainzService.swift`

### Views
- `VinylVault/Views/Components/ReviewCardView.swift`

### Updated Files
- `VinylVault/Views/ReleaseDetailView.swift` (already in project, updated)

## 🔧 How to Add Files to Xcode Project

### Method 1: Add Files via Xcode (Recommended)

1. **Open Xcode** and your VinylVault project
2. **Right-click** on the `Models` folder in the Project Navigator
3. Select **"Add Files to VinylVault"**
4. Navigate to and select `MusicBrainzModels.swift`
5. Make sure **"Copy items if needed"** is UNCHECKED (files are already in place)
6. Make sure **"Add to targets: VinylVault"** is CHECKED
7. Click **Add**

8. **Repeat** for the Services folder:
   - Right-click on `Services` folder
   - Add Files to VinylVault
   - Select `MusicBrainzService.swift` and `CritiqueBrainzService.swift`
   - Ensure target is checked, click Add

9. **Repeat** for the Views/Components folder:
   - Right-click on `Views/Components` folder (create Components folder if it doesn't exist)
   - Add Files to VinylVault
   - Select `ReviewCardView.swift`
   - Ensure target is checked, click Add

### Method 2: Add Files via Project Navigator

1. **Open Xcode** and your VinylVault project
2. In the **Project Navigator**, locate each file
3. If files appear **gray** or **without a checkbox**, they're not in the target
4. **Select** each file
5. In the **File Inspector** (right sidebar), check the **Target Membership** box for VinylVault

### Method 3: Rebuild Xcode Project File (If above methods don't work)

If files still don't appear or compile:

1. Close Xcode
2. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
3. Open Terminal and navigate to the SecondSpin folder
4. Run: `rm -rf *.xcodeproj`
5. Run: `xcodegen` (if you use XcodeGen) or recreate project
6. Reopen in Xcode

## 🧪 Verify Installation

After adding files to the project, **build** the project (⌘+B):

1. All compilation errors should be resolved
2. You should see no "Cannot find type" errors
3. The app should build successfully

## 📱 Test the Integration

1. **Run the app** on simulator or device
2. **Navigate** to any album in your collection
3. **Open the detail view**
4. You should see:
   - ⭐ Community Rating section (if data available)
   - 📝 Reviews section (if reviews available)
   - Loading indicators during first load
   - Instant display on subsequent loads (cached)

## 🐛 Troubleshooting

### "Cannot find type 'MusicBrainzRating'" error
- **Cause**: File not added to target
- **Fix**: Follow Method 1 or 2 above to add files to target

### "Cannot find 'MusicBrainzService'" error
- **Cause**: Service file not in target
- **Fix**: Add MusicBrainzService.swift to target membership

### "Cannot find 'ReviewCardView'" error
- **Cause**: View component not in target
- **Fix**: Add ReviewCardView.swift to target membership

### Files appear but still won't compile
- **Clean Build Folder**: ⌘+Shift+K
- **Delete Derived Data**: Xcode → Preferences → Locations → Derived Data → Delete
- **Restart Xcode**

## 📚 API Information

### MusicBrainz
- **Endpoint**: `https://musicbrainz.org/ws/2/`
- **Rate Limit**: 1 request per second (handled automatically)
- **Cache Duration**: 7 days
- **No API Key Required** for non-commercial use

### CritiqueBrainz
- **Endpoint**: `https://critiquebrainz.org/ws/1/`
- **Rate Limit**: 1 request per second (handled automatically)
- **Cache Duration**: 7 days
- **No API Key Required**

## ✅ Features Included

- ⭐ Community ratings (1-5 stars) with vote counts
- 🏷️ MusicBrainz genre tags with popularity counts
- 📝 Album reviews from CritiqueBrainz
- 👍 Review vote counts (thumbs up/down)
- 🔗 Links to original review sources
- 📱 Expandable review text
- 💾 Smart 7-day caching
- ⚡ Automatic rate limiting
- 🎨 Clean, native iOS design
- 🌓 Dark mode support
- 🔄 Graceful error handling

## 🚀 Next Steps

Once files are properly added to the Xcode project:

1. **Build and Run** the app
2. **Open an album** from your collection
3. **Observe** the new rating and review sections
4. **Test caching** by closing and reopening the same album
5. **Verify** smooth scrolling and UI performance

Enjoy your enhanced vinyl collection app! 🎵
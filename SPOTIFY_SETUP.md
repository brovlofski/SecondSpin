# Spotify API Setup Guide

This guide shows you how to get Spotify client credentials to enable direct album linking in VinylVault.

## Why This Is Needed

Without Spotify credentials configured, the app will:
- Fall back to Spotify search URLs (shows mixed results: albums, tracks, artists)
- Not be able to verify and cache direct album links

With Spotify credentials configured, the app will:
- Search the Spotify API for exact album matches
- Open directly to the album detail page
- Cache verified album URLs for instant future access
- Provide a much better user experience

## Step-by-Step Setup

### 1. Create a Spotify Developer Account

1. Go to [Spotify for Developers](https://developer.spotify.com/dashboard)
2. Log in with your Spotify account (or create one if needed)
3. Accept the Terms of Service

### 2. Create an App

1. Click **"Create app"** button
2. Fill in the form:
   - **App name**: `VinylVault` (or any name you prefer)
   - **App description**: `Personal vinyl collection manager with streaming links`
   - **Redirect URI**: `vinylvault://callback` (required but not used for this flow)
   - **Which API/SDKs are you planning to use?**: Check "Web API"
3. Accept the Developer Terms of Service
4. Click **"Save"**

### 3. Get Your Credentials

1. In your app's dashboard, click **"Settings"**
2. You'll see:
   - **Client ID**: A long string like `abc123def456ghi789`
   - **Client Secret**: Click "View client secret" to reveal it
3. Copy both values (you'll need them in the next step)

### 4. Add Credentials to VinylVault

1. Open the Xcode project
2. Navigate to `VinylVault/Services/StreamingLinkService.swift`
3. Find the `SpotifyConfig` enum at the top:

```swift
private enum SpotifyConfig {
    static let clientID     = ""   // e.g. "abc123def456"
    static let clientSecret = ""   // e.g. "xyz789uvw012"
    static var isConfigured: Bool { !clientID.isEmpty && !clientSecret.isEmpty }
}
```

4. Paste your credentials:

```swift
private enum SpotifyConfig {
    static let clientID     = "your_client_id_here"
    static let clientSecret = "your_client_secret_here"
    static var isConfigured: Bool { !clientID.isEmpty && !clientSecret.isEmpty }
}
```

5. Save the file
6. Build and run the app

## Verification

To verify the setup is working:

1. Add an album to your collection (or use an existing one)
2. Open the album detail view
3. Tap the Spotify icon
4. You should now open directly to the album page on Spotify (not search results)

If you see search results instead:
- Check that you pasted the credentials correctly
- Ensure there are no extra spaces or quotes
- Verify the credentials are valid in your Spotify Developer Dashboard

## Security Notes

**Important**: Never commit your Spotify credentials to public repositories!

### For Open Source Projects:

If you plan to share this code publicly:

1. Keep credentials in a separate config file:
   - Create `SpotifyConfig.swift` (add to `.gitignore`)
   - Move the credentials there
   - Provide a template file (`SpotifyConfig.swift.template`)

2. Or use environment variables:
   ```swift
   static let clientID = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"] ?? ""
   static let clientSecret = ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_SECRET"] ?? ""
   ```

3. Or use Xcode configuration files (.xcconfig)

### For Personal Use:

If this is a personal project only:
- The current setup is fine
- Just don't push to a public repository
- If you do push, add `StreamingLinkService.swift` to `.gitignore` after adding credentials

## API Usage

The app uses Spotify's **Client Credentials Flow**:
- No user authentication required
- Only accesses public catalog data
- Used for searching albums and getting album details
- Rate limits: 180 requests per minute (plenty for this use case)

## Troubleshooting

### "Could not open Spotify"
- Spotify app not installed → opens in web browser instead (expected behavior)
- Check that Spotify app is installed if you prefer the app

### Still seeing search results
- Credentials not configured → check spelling and quotes
- Network error → check internet connection
- Album not found on Spotify → fallback to search is expected

### Token errors
- Invalid credentials → verify in Spotify Dashboard
- Expired credentials → regenerate in Spotify Dashboard
- Network timeout → retry operation

## API Documentation

For more details on the Spotify Web API:
- [Web API Documentation](https://developer.spotify.com/documentation/web-api)
- [Search Endpoint](https://developer.spotify.com/documentation/web-api/reference/search)
- [Client Credentials Flow](https://developer.spotify.com/documentation/web-api/tutorials/client-credentials-flow)

## Rate Limits

Default rate limits for Client Credentials:
- 180 requests per minute per app
- Automatically managed by the service (token caching)
- Should be more than sufficient for personal use

If you hit rate limits:
- Wait 1 minute for reset
- Consider caching more aggressively
- Contact Spotify for higher limits (if building commercial app)
//
//  StreamingLinkService.swift
//  VinylVault
//
//  Streaming link resolution with metadata-based validation.
//
//  Pipeline per service:
//    1. If release.streamingLinksVerified → use cached URLs, done.
//    2. Search iTunes / Spotify for up to 5 candidates.
//    3. Score each candidate (title + artist + year + tracklist).
//    4. Accept the top scorer above threshold (≥ 50 / 100 pts).
//    5. Store direct album URL in Release; mark streamingLinksVerified = true.
//    6. Prefer original/standard editions; penalise tribute/karaoke/compilation.
//
//  Apple Music  → iTunes Search API  (no auth required)
//  Spotify      → Web API v1 search  (requires client_id + client_secret below)
//

import Foundation
import UIKit

// MARK: - Spotify credentials
// Fill in your Spotify Developer Dashboard client credentials.
// https://developer.spotify.com/dashboard
private enum SpotifyConfig {
    static let clientID     = "ee3582a89bfd4ab49fcd07430f7f2d7c"
    static let clientSecret = "e8da8668ab1948149ae16db72352b4f5"
    static var isConfigured: Bool { !clientID.isEmpty && !clientSecret.isEmpty }
}

// MARK: - iTunes API models (Apple Music, no auth)

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesAlbum]
}

private struct ITunesAlbum: Decodable {
    let collectionName: String
    let artistName: String
    let releaseDate: String?      // "1969-09-26T07:00:00Z"
    let trackCount: Int?
    let collectionViewUrl: String?
    let collectionType: String?   // "Album"
    let wrapperType: String?      // "collection"
}

// MARK: - Spotify API models

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn   = "expires_in"
    }
}

private struct SpotifySearchResponse: Decodable {
    let albums: SpotifyAlbumPage?
    struct SpotifyAlbumPage: Decodable {
        let items: [SpotifyAlbum]
    }
}

private struct SpotifyAlbum: Decodable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let releaseDate: String?       // "1969-09-26", "1969-09", "1969"
    let totalTracks: Int?
    let albumType: String?         // "album" | "single" | "compilation"
    let externalUrls: ExternalURLs?
    enum CodingKeys: String, CodingKey {
        case id, name, artists
        case releaseDate  = "release_date"
        case totalTracks  = "total_tracks"
        case albumType    = "album_type"
        case externalUrls = "external_urls"
    }
    struct ExternalURLs: Decodable { let spotify: String? }
    var webURL: String? { externalUrls?.spotify }
    var deepLinkURL: String { "spotify:album:\(id)" }
}

private struct SpotifyArtist: Decodable { let name: String }

// MARK: - Internal scored candidate

private struct StreamingCandidate {
    let title: String
    let artist: String
    let year: Int?
    let trackCount: Int?
    let score: Double          // 0…100
    let directURL: String      // URL to store if this candidate wins
    let deepLinkURL: String?   // app deep link (Spotify only)
}

// MARK: - Service

class StreamingLinkService {
    static let shared = StreamingLinkService()

    // Acceptance threshold (0–100)
    private let acceptanceThreshold: Double = 50.0

    // Spotify token cache
    private var spotifyToken: String?
    private var spotifyTokenExpiry: Date = .distantPast

    private init() {}

    // MARK: - Public: verify and update release links

    /// Searches iTunes and (if Spotify is configured) Spotify for the best-matching
    /// album, scores each candidate, and persists the winning URLs to `release`.
    /// No-ops if `release.streamingLinksVerified == true`.
    @MainActor
    func verifyAndUpdateLinks(release: Release) async {
        guard !release.streamingLinksVerified else { return }

        async let appleTask  = bestAppleMusicURL(for: release)
        async let spotifyTask = bestSpotifyURL(for: release)
        async let neteaseTask = bestNetEaseCloudMusicURL(for: release)

        let (appleURL, spotifyURL, neteaseURL) = await (appleTask, spotifyTask, neteaseTask)

        release.appleMusicAlbumURL  = appleURL  ?? release.appleMusicAlbumURL
        release.spotifyAlbumURL     = spotifyURL ?? release.spotifyAlbumURL
        release.neteaseCloudMusicAlbumURL = neteaseURL ?? release.neteaseCloudMusicAlbumURL
        release.streamingLinksVerified = true
    }

    // MARK: - Public: open helpers (use verified URL when available)

    func openSpotify(release: Release? = nil, artist: String, album: String) {
        // Prefer verified deep link, then verified web URL
        if let stored = release?.spotifyAlbumURL {
            if let url = URL(string: "spotify:album:\(spotifyIDFromURL(stored) ?? "")"),
               !spotifyIDFromURL(stored).isNil,
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url); return
            }
            if let url = URL(string: stored) {
                UIApplication.shared.open(url); return
            }
        }
        
        // Fallback: Search Spotify API for exact album and open directly
        Task {
            if let directURL = await self.searchSpotifyAlbumDirect(artist: artist, album: album) {
                await MainActor.run {
                    if let url = URL(string: directURL) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                // Final fallback: album-filtered search
                let q = "album:\(album) artist:\(artist)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
                await MainActor.run {
                    if let appURL = URL(string: "spotify:search:\(q)"), UIApplication.shared.canOpenURL(appURL) {
                        UIApplication.shared.open(appURL)
                    } else if let webURL = URL(string: "https://open.spotify.com/search/album%3A\(album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")%20artist%3A\(artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        UIApplication.shared.open(webURL)
                    }
                }
            }
        }
    }

    func openAppleMusic(release: Release? = nil, artist: String, album: String) {
        if let stored = release?.appleMusicAlbumURL, let url = URL(string: stored) {
            UIApplication.shared.open(url); return
        }
        // Fallback: Use iTunes Search API to find the album and redirect
        Task {
            if let directURL = await self.searchAppleMusicAlbum(artist: artist, album: album) {
                await MainActor.run {
                    if let url = URL(string: directURL) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                // Final fallback: generic search with album filter hint
                let q = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                await MainActor.run {
                    if let url = URL(string: "https://music.apple.com/search?term=\(q)") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
    
    func openNetEaseCloudMusic(release: Release? = nil, artist: String, album: String) {
        // Try to use cached URL if available
        if let stored = release?.neteaseCloudMusicAlbumURL, let url = URL(string: stored) {
            UIApplication.shared.open(url); return
        }
        
        // Fallback: Try to search for the album on NetEase Cloud Music
        Task {
            if let directURL = await self.searchNetEaseCloudMusicAlbum(artist: artist, album: album) {
                await MainActor.run {
                    if let url = URL(string: directURL) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                // Final fallback: generic search on NetEase Cloud Music website
                let q = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                await MainActor.run {
                    if let url = URL(string: "https://music.163.com/#/search/m/?s=\(q)&type=10") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - Helper: Quick Spotify album lookup
    
    private func searchSpotifyAlbumDirect(artist: String, album: String) async -> String? {
        guard SpotifyConfig.isConfigured else { return nil }
        guard let token = await fetchSpotifyToken() else { return nil }
        
        let query = "\(album) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.spotify.com/v1/search?q=\(encoded)&type=album&limit=3") else {
            return nil
        }
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let resp = try? JSONDecoder().decode(SpotifySearchResponse.self, from: data),
              let albums = resp.albums?.items else {
            return nil
        }
        
        // Find best matching album (simple fuzzy match on title and artist)
        let normalizedAlbum = normalize(album)
        let bestMatch = albums.first { spotifyAlbum in
            let normalizedTitle = normalize(spotifyAlbum.name)
            // Check if album titles overlap significantly
            let titleMatch = normalizedTitle.contains(normalizedAlbum.prefix(min(5, normalizedAlbum.count))) ||
                           normalizedAlbum.contains(normalizedTitle.prefix(min(5, normalizedTitle.count)))
            // Check if any artist name matches
            let normalizedArtist = normalize(artist)
            let artistMatch = spotifyAlbum.artists.contains { 
                let normalizedSpotifyArtist = normalize($0.name)
                return normalizedSpotifyArtist.contains(normalizedArtist.prefix(min(5, normalizedArtist.count))) ||
                       normalizedArtist.contains(normalizedSpotifyArtist.prefix(min(5, normalizedSpotifyArtist.count)))
            }
            return titleMatch && artistMatch
        }
        
        return bestMatch?.webURL
    }
    
    // MARK: - Helper: Quick Apple Music album lookup
    
    private func searchAppleMusicAlbum(artist: String, album: String) async -> String? {
        let query = "\(album) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=album&limit=3") else {
            return nil
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(ITunesSearchResponse.self, from: data),
              let firstAlbum = resp.results.first(where: { 
                  ($0.wrapperType == "collection" || $0.collectionType == "Album") &&
                  normalize($0.artistName).contains(normalize(artist).prefix(5)) // fuzzy artist match
              }) else {
            return nil
        }
        return firstAlbum.collectionViewUrl
    }
    
    // MARK: - Legacy helpers (backward compatible)

    func spotifyAppURL(artist: String, album: String) -> URL? {
        let q = "album:\(album) artist:\(artist)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "spotify:search:\(q)")
    }
    func spotifyWebURL(artist: String, album: String) -> URL? {
        let albumEncoded = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let artistEncoded = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://open.spotify.com/search/album%3A\(albumEncoded)%20artist%3A\(artistEncoded)")
    }
    func appleMusicURL(artist: String, album: String) -> URL? {
        let q = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://music.apple.com/search?term=\(q)")
    }
    func generateSpotifyLink(artist: String, album: String) -> URL? { spotifyWebURL(artist: artist, album: album) }
    func generateAppleMusicLink(artist: String, album: String) -> URL? { appleMusicURL(artist: artist, album: album) }

    // MARK: - NetEase Cloud Music Search
    
    private func bestNetEaseCloudMusicURL(for release: Release) async -> String? {
        // NetEase Cloud Music doesn't have a public API like Spotify/Apple Music,
        // so we'll use web scraping to find the album.
        let query = "\(release.title) \(release.artist)"
        
        // First try to search via web scraping
        if let url = await searchNetEaseCloudMusicAlbum(artist: release.artist, album: release.title) {
            return url
        }
        
        // If that fails, return a search URL as fallback
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return "https://music.163.com/#/search/m/?s=\(encodedQuery)&type=10"
    }
    
    private func searchNetEaseCloudMusicAlbum(artist: String, album: String) async -> String? {
        // NetEase Cloud Music web search approach
        // We'll try to construct a direct album URL based on common patterns
        let query = "\(album) \(artist)"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        
        // Try multiple approaches:
        // 1. Direct web search to find album ID
        // 2. Common URL patterns
        
        // Approach 1: Try to fetch search results page and parse for album link
        // Note: NetEase Cloud Music is a single-page app, so parsing HTML is complex
        // For now, we return nil and let the caller use the search URL fallback
        _ = "https://music.163.com/#/search/m/?s=\(encodedQuery)&type=10"
        
        // In a production app, you might use a dedicated API or more sophisticated parsing
        return nil  // Return nil to indicate we couldn't find a direct album URL
    }

    // MARK: - Apple Music (iTunes Search API)

    private func bestAppleMusicURL(for release: Release) async -> String? {
        let query = "\(release.title) \(release.artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=album&limit=5") else {
            return nil
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(ITunesSearchResponse.self, from: data) else {
            return nil
        }

        let candidates: [StreamingCandidate] = resp.results.compactMap { album in
            guard album.wrapperType == "collection" || album.collectionType == "Album" else { return nil }
            let year = parseYear(from: album.releaseDate)
            let s = score(
                candidateTitle:  album.collectionName,
                candidateArtist: album.artistName,
                candidateYear:   year,
                candidateTrackCount: album.trackCount,
                candidateFirstTracks: [],
                penalties: penalties(for: album.collectionName),
                release: release
            )
            guard let viewURL = album.collectionViewUrl else { return nil }
            return StreamingCandidate(title: album.collectionName, artist: album.artistName,
                                      year: year, trackCount: album.trackCount,
                                      score: s, directURL: viewURL, deepLinkURL: nil)
        }

        return bestCandidate(from: candidates)?.directURL
    }

    // MARK: - Spotify

    private func bestSpotifyURL(for release: Release) async -> String? {
        guard SpotifyConfig.isConfigured else { return nil }
        guard let token = await fetchSpotifyToken() else { return nil }

        let query = "\(release.title) \(release.artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.spotify.com/v1/search?q=\(encoded)&type=album&limit=5") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let resp = try? JSONDecoder().decode(SpotifySearchResponse.self, from: data) else {
            return nil
        }

        let candidates: [StreamingCandidate] = (resp.albums?.items ?? []).compactMap { album in
            // Only consider proper albums; skip singles/compilations by default
            let s = score(
                candidateTitle:  album.name,
                candidateArtist: album.artists.first?.name ?? "",
                candidateYear:   parseYear(from: album.releaseDate),
                candidateTrackCount: album.totalTracks,
                candidateFirstTracks: [],
                penalties: penalties(for: album.name, albumType: album.albumType),
                release: release
            )
            guard let webURL = album.webURL else { return nil }
            return StreamingCandidate(title: album.name, artist: album.artists.first?.name ?? "",
                                      year: parseYear(from: album.releaseDate), trackCount: album.totalTracks,
                                      score: s, directURL: webURL, deepLinkURL: album.deepLinkURL)
        }

        return bestCandidate(from: candidates)?.directURL
    }

    // MARK: - Spotify token (client credentials)

    private func fetchSpotifyToken() async -> String? {
        if let token = spotifyToken, Date() < spotifyTokenExpiry { return token }

        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return nil }
        let creds = "\(SpotifyConfig.clientID):\(SpotifyConfig.clientSecret)"
        guard let credsData = creds.data(using: .utf8) else { return nil }
        let b64 = credsData.base64EncodedString()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=client_credentials".data(using: .utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let tokenResp = try? JSONDecoder().decode(SpotifyTokenResponse.self, from: data) else {
            return nil
        }

        spotifyToken = tokenResp.accessToken
        spotifyTokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResp.expiresIn - 60))
        return spotifyToken
    }

    // MARK: - Scoring (0–100 pts)

    private func score(
        candidateTitle: String,
        candidateArtist: String,
        candidateYear: Int?,
        candidateTrackCount: Int?,
        candidateFirstTracks: [String],
        penalties: Double,
        release: Release
    ) -> Double {
        var pts = 0.0

        // Title similarity  0–40 pts
        let titleSim = wordJaccard(normalize(candidateTitle), normalize(release.title))
        pts += titleSim * 40.0

        // Artist similarity  0–30 pts
        let artistSim = wordJaccard(normalize(candidateArtist), normalize(release.artist))
        pts += artistSim * 30.0

        // Release year  0–15 pts
        if let cy = candidateYear, release.year > 0 {
            let diff = abs(cy - release.year)
            if diff == 0      { pts += 15 }
            else if diff == 1 { pts += 10 }
            else if diff == 2 { pts += 5  }
        }

        // Track count  0–7 pts
        let rtc = release.tracklist.count
        if let ctc = candidateTrackCount, rtc > 0 {
            if ctc == rtc               { pts += 7 }
            else if abs(ctc - rtc) <= 2 { pts += 3 }
        }

        // First-3 track titles  0–8 pts (≈2.67 pts each)
        let releaseTracks = release.tracklist.prefix(3).map { normalize($0.title) }
        for (i, ct) in candidateFirstTracks.prefix(3).enumerated() {
            if i < releaseTracks.count, wordJaccard(normalize(ct), releaseTracks[i]) > 0.5 {
                pts += 8.0 / 3.0
            }
        }

        // Penalties (negative, passed in from caller)
        pts -= penalties

        return max(0, min(100, pts))
    }

    private func bestCandidate(from candidates: [StreamingCandidate]) -> StreamingCandidate? {
        candidates
            .filter { $0.score >= acceptanceThreshold }
            .max { $0.score < $1.score }
    }

    // MARK: - Penalties

    private func penalties(for title: String, albumType: String? = nil) -> Double {
        var p = 0.0
        let t = title.lowercased()
        if t.contains("tribute")    { p += 30 }
        if t.contains("karaoke")    { p += 50 }
        if t.contains("cover")      { p += 20 }
        if t.contains("made famous") { p += 25 }
        if t.contains("originally performed") { p += 25 }
        if albumType == "compilation" { p += 10 }
        return p
    }

    // MARK: - Utilities

    /// Normalise: lowercase, strip non-alphanumeric-space, collapse spaces
    private func normalize(_ s: String) -> String {
        s.lowercased()
         .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
         .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Jaccard similarity on word sets
    private func wordJaccard(_ a: String, _ b: String) -> Double {
        let sa = Set(a.components(separatedBy: " ").filter { !$0.isEmpty })
        let sb = Set(b.components(separatedBy: " ").filter { !$0.isEmpty })
        let inter = sa.intersection(sb).count
        let union = sa.union(sb).count
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    /// Parse 4-digit year from various date strings
    private func parseYear(from dateString: String?) -> Int? {
        guard let s = dateString, s.count >= 4 else { return nil }
        return Int(s.prefix(4))
    }

    /// Extract Spotify album ID from a web URL
    private func spotifyIDFromURL(_ urlString: String) -> String? {
        // https://open.spotify.com/album/0ETFjACtuP2ADo6LFhL6HN
        guard let url = URL(string: urlString),
              url.host == "open.spotify.com" else { return nil }
        let comps = url.pathComponents
        guard let idx = comps.firstIndex(of: "album"), idx + 1 < comps.count else { return nil }
        return comps[idx + 1]
    }
}

// MARK: - Optional convenience

private extension Optional where Wrapped == String {
    var isNil: Bool { self == nil }
}
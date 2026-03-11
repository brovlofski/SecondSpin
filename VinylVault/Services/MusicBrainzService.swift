//
//  MusicBrainzService.swift
//  VinylVault
//
//  Service for fetching album ratings and metadata from MusicBrainz API
//

import Foundation

actor MusicBrainzService {
    static let shared = MusicBrainzService()
    
    private let baseURL = "https://musicbrainz.org/ws/2"
    private let userAgent = "VinylVault/1.0 (https://github.com/secondspin/vinylvault)"
    
    // Cache for MBID lookups (artist+album -> MBID)
    private var mbidCache: [String: String] = [:]
    // Cache for full data (MBID -> CachedMusicBrainzData)
    private var dataCache: [String: CachedMusicBrainzData] = [:]
    
    // Rate limiting: 1 request per second
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 1.0
    
    private init() {
        Task {
            await loadCache()
        }
    }
    
    // MARK: - Public Methods
    
    /// Search for a release group by artist and album name
    func searchReleaseGroup(artist: String, album: String) async throws -> MusicBrainzReleaseGroup? {
        let cacheKey = "\(artist.lowercased())|\(album.lowercased())"
        
        // Check MBID cache first
        if let cachedMBID = mbidCache[cacheKey] {
            // Try to get full data from cache
            if let cachedData = dataCache[cachedMBID], !cachedData.isExpired {
                print("Using cached MusicBrainz data for: \(artist) - \(album)")
                return nil // We'll use cached data directly
            }
        }
        
        await enforceRateLimit()
        
        // Build search query
        let query = "artist:\"\(artist)\" AND releasegroup:\"\(album)\""
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw MusicBrainzError.invalidQuery
        }
        
        let urlString = "\(baseURL)/release-group?query=\(encodedQuery)&limit=5&fmt=json"
        guard let url = URL(string: urlString) else {
            throw MusicBrainzError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicBrainzError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw MusicBrainzError.httpError(httpResponse.statusCode)
        }
        
        let searchResponse = try JSONDecoder().decode(MusicBrainzSearchResponse.self, from: data)
        
        // Find best match (highest score)
        guard let bestMatch = searchResponse.releaseGroups.max(by: { ($0.score ?? 0) < ($1.score ?? 0) }) else {
            return nil
        }
        
        // Cache the MBID
        mbidCache[cacheKey] = bestMatch.id
        saveCache()
        
        return bestMatch
    }
    
    /// Fetch detailed information for a release group by MBID
    func fetchReleaseGroupDetails(mbid: String) async throws -> (rating: MusicBrainzRating?, genres: [MusicBrainzGenre]) {
        // Check cache first
        if let cachedData = dataCache[mbid], !cachedData.isExpired {
            print("Using cached MusicBrainz data for MBID: \(mbid)")
            return (cachedData.rating, cachedData.genres)
        }
        
        await enforceRateLimit()
        
        let urlString = "\(baseURL)/release-group/\(mbid)?inc=ratings+genres&fmt=json"
        guard let url = URL(string: urlString) else {
            throw MusicBrainzError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicBrainzError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw MusicBrainzError.httpError(httpResponse.statusCode)
        }
        
        let releaseGroup = try JSONDecoder().decode(MusicBrainzReleaseGroup.self, from: data)
        
        // Cache the results
        let cachedData = CachedMusicBrainzData(
            mbid: mbid,
            rating: releaseGroup.rating,
            genres: releaseGroup.genres ?? [],
            cachedDate: Date()
        )
        dataCache[mbid] = cachedData
        saveCache()
        
        return (releaseGroup.rating, releaseGroup.genres ?? [])
    }
    
    /// Get rating and genres for an album (search + fetch in one call)
    func getRatingAndGenres(artist: String, album: String) async throws -> (rating: MusicBrainzRating?, genres: [MusicBrainzGenre], mbid: String?) {
        // First, search for the release group
        if let releaseGroup = try await searchReleaseGroup(artist: artist, album: album) {
            let mbid = releaseGroup.id
            
            // If search response already includes rating and genres, use them
            if let rating = releaseGroup.rating, let genres = releaseGroup.genres {
                return (rating, genres, mbid)
            }
            
            // Otherwise fetch details
            let (rating, genres) = try await fetchReleaseGroupDetails(mbid: mbid)
            return (rating, genres, mbid)
        }
        
        return (nil, [], nil)
    }
    
    /// Get cached MBID for artist/album combination
    func getCachedMBID(artist: String, album: String) -> String? {
        let cacheKey = "\(artist.lowercased())|\(album.lowercased())"
        return mbidCache[cacheKey]
    }
    
    /// Get cached data for an MBID
    func getCachedData(mbid: String) -> CachedMusicBrainzData? {
        guard let cached = dataCache[mbid], !cached.isExpired else {
            return nil
        }
        return cached
    }
    
    // MARK: - Private Methods
    
    private func enforceRateLimit() async {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < minimumRequestInterval {
                let sleepTime = minimumRequestInterval - timeSinceLastRequest
                try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }
    
    // MARK: - Cache Persistence
    
    private func loadCache() async {
        let defaults = UserDefaults.standard
        
        if let mbidData = defaults.data(forKey: "MusicBrainzMBIDCache"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: mbidData) {
            mbidCache = decoded
        }
        
        if let dataData = defaults.data(forKey: "MusicBrainzDataCache"),
           let decoded = try? JSONDecoder().decode([String: CachedMusicBrainzData].self, from: dataData) {
            // Filter out expired entries
            dataCache = decoded.filter { !$0.value.isExpired }
        }
    }
    
    private func saveCache() {
        let defaults = UserDefaults.standard
        
        if let encoded = try? JSONEncoder().encode(mbidCache) {
            defaults.set(encoded, forKey: "MusicBrainzMBIDCache")
        }
        
        // Only save non-expired data
        let validData = dataCache.filter { !$0.value.isExpired }
        if let encoded = try? JSONEncoder().encode(validData) {
            defaults.set(encoded, forKey: "MusicBrainzDataCache")
        }
    }
    
    /// Clear all cached data
    func clearCache() {
        mbidCache.removeAll()
        dataCache.removeAll()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "MusicBrainzMBIDCache")
        defaults.removeObject(forKey: "MusicBrainzDataCache")
    }
    
    /// Clear cache for a specific artist/album combination
    func clearCache(forArtist artist: String, album: String) async {
        let cacheKey = "\(artist.lowercased())|\(album.lowercased())"
        
        // Remove from MBID cache
        if let mbid = mbidCache.removeValue(forKey: cacheKey) {
            // Also remove from data cache if present
            dataCache.removeValue(forKey: mbid)
            
            // Save updated caches
            saveCache()
            print("MusicBrainz cache cleared for: \(artist) - \(album)")
        }
    }
}

// MARK: - Error Types

enum MusicBrainzError: LocalizedError {
    case invalidURL
    case invalidQuery
    case invalidResponse
    case httpError(Int)
    case decodingError
    case noResults
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidQuery:
            return "Invalid search query"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .noResults:
            return "No results found"
        }
    }
}
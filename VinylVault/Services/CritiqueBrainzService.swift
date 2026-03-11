//
//  CritiqueBrainzService.swift
//  VinylVault
//
//  Service for fetching album reviews from CritiqueBrainz API
//

import Foundation

actor CritiqueBrainzService {
    static let shared = CritiqueBrainzService()
    
    private let baseURL = "https://critiquebrainz.org/ws/1"
    private let userAgent = "VinylVault/1.0 (https://github.com/secondspin/vinylvault)"
    
    // Cache for reviews (MBID -> [AlbumReview])
    private var reviewsCache: [String: CachedReviews] = [:]
    
    // Rate limiting: 1 request per second
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 1.0
    
    private init() {
        Task {
            await loadCache()
        }
    }
    
    // MARK: - Public Methods
    
    /// Fetch reviews for a release group by MusicBrainz ID
    func fetchReviews(mbid: String, limit: Int = 10) async throws -> [AlbumReview] {
        // Check cache first
        if let cached = reviewsCache[mbid], !cached.isExpired {
            print("Using cached reviews for MBID: \(mbid)")
            return cached.reviews
        }
        
        await enforceRateLimit()
        
        let urlString = "\(baseURL)/review/?release_group=\(mbid)&limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw CritiqueBrainzError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CritiqueBrainzError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw CritiqueBrainzError.httpError(httpResponse.statusCode)
        }
        
        let reviewResponse = try JSONDecoder().decode(CritiqueBrainzResponse.self, from: data)
        
        // Cache the results
        let cached = CachedReviews(reviews: reviewResponse.reviews, cachedDate: Date())
        reviewsCache[mbid] = cached
        saveCache()
        
        return reviewResponse.reviews
    }
    
    /// Get cached reviews for an MBID
    func getCachedReviews(mbid: String) -> [AlbumReview]? {
        guard let cached = reviewsCache[mbid], !cached.isExpired else {
            return nil
        }
        return cached.reviews
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
        
        if let data = defaults.data(forKey: "CritiqueBrainzCache"),
           let decoded = try? JSONDecoder().decode([String: CachedReviews].self, from: data) {
            // Filter out expired entries
            reviewsCache = decoded.filter { !$0.value.isExpired }
        }
    }
    
    private func saveCache() {
        let defaults = UserDefaults.standard
        
        // Only save non-expired data
        let validData = reviewsCache.filter { !$0.value.isExpired }
        if let encoded = try? JSONEncoder().encode(validData) {
            defaults.set(encoded, forKey: "CritiqueBrainzCache")
        }
    }
    
    /// Clear all cached data
    func clearCache() {
        reviewsCache.removeAll()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "CritiqueBrainzCache")
    }
    
    /// Clear cache for a specific MBID
    func clearCache(forMBID mbid: String) async {
        reviewsCache.removeValue(forKey: mbid)
        
        // Save updated cache
        saveCache()
        print("CritiqueBrainz cache cleared for MBID: \(mbid)")
    }
}

// MARK: - Supporting Types

struct CachedReviews: Codable {
    let reviews: [AlbumReview]
    let cachedDate: Date
    
    var isExpired: Bool {
        // Cache expires after 7 days
        Calendar.current.dateComponents([.day], from: cachedDate, to: Date()).day ?? 0 > 7
    }
}

// MARK: - Error Types

enum CritiqueBrainzError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError
    case noReviews
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        case .noReviews:
            return "No reviews found"
        }
    }
}
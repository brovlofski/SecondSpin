//
//  PitchforkService.swift
//  VinylVault
//
//  Service for fetching Pitchfork year-end list data from AOTY API
//

import Foundation

actor PitchforkService {
    static let shared = PitchforkService()
    
    private let baseURL = "https://albums-aoty-api-production.up.railway.app"
    private let cache = NSCache<NSString, CacheEntry>()
    
    private init() {
        cache.countLimit = 100 // Cache up to 100 artist queries
    }
    
    // MARK: - Cache Entry
    private class CacheEntry {
        let data: PitchforkArtistYearEndData?
        let timestamp: Date
        
        init(data: PitchforkArtistYearEndData?) {
            self.data = data
            self.timestamp = Date()
        }
        
        var isExpired: Bool {
            // Cache for 7 days (year-end lists don't change often)
            Date().timeIntervalSince(timestamp) > 7 * 24 * 60 * 60
        }
    }
    
    // MARK: - Public Methods
    
    /// Fetch year-end list appearances for an artist
    func fetchYearEndListData(for artist: String) async throws -> PitchforkArtistYearEndData? {
        let cacheKey = artist.lowercased() as NSString
        
        // Check cache first
        if let cached = cache.object(forKey: cacheKey), !cached.isExpired {
            print("✅ [Pitchfork] Using cached data for '\(artist)'")
            return cached.data
        }
        
        // Encode artist name for URL
        guard let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            print("❌ [Pitchfork] Failed to encode artist name: \(artist)")
            return nil
        }
        
        let urlString = "\(baseURL)/all/\(encodedArtist)"
        
        guard let url = URL(string: urlString) else {
            print("❌ [Pitchfork] Invalid URL: \(urlString)")
            return nil
        }
        
        print("🔍 [Pitchfork] Fetching year-end data for '\(artist)'...")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [Pitchfork] Invalid response type")
                return nil
            }
            
            print("📡 [Pitchfork] Response status: \(httpResponse.statusCode)")
            
            // Handle 404 - artist not found in year-end lists
            if httpResponse.statusCode == 404 || httpResponse.statusCode == 400 {
                print("ℹ️ [Pitchfork] Artist '\(artist)' not found in year-end lists")
                cache.setObject(CacheEntry(data: nil), forKey: cacheKey)
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                print("❌ [Pitchfork] HTTP error: \(httpResponse.statusCode)")
                return nil
            }
            
            // Try to decode the response
            let decoder = JSONDecoder()
            let yearEndData = try decoder.decode(PitchforkArtistYearEndData.self, from: data)
            
            print("✅ [Pitchfork] Found \(yearEndData.entries.count) year-end list appearance(s) for '\(artist)'")
            
            // Log appearances
            for (year, entry) in yearEndData.entries.sorted(by: { $0.key > $1.key }) {
                print("   📍 \(year): #\(entry.rank) - \(entry.album)")
            }
            
            // Cache the result
            cache.setObject(CacheEntry(data: yearEndData), forKey: cacheKey)
            
            return yearEndData
            
        } catch let DecodingError.dataCorrupted(context) {
            print("❌ [Pitchfork] Decoding error - data corrupted: \(context)")
            return nil
        } catch let DecodingError.keyNotFound(key, context) {
            print("❌ [Pitchfork] Decoding error - key not found: \(key.stringValue), \(context)")
            return nil
        } catch {
            print("❌ [Pitchfork] Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Get badge data for a specific album
    func getBadge(for artist: String, album: String) async -> PitchforkBadge? {
        guard let yearEndData = try? await fetchYearEndListData(for: artist) else {
            return nil
        }
        
        // Find matching album in any year
        for (year, entry) in yearEndData.entries {
            if albumTitlesMatch(entry.album, album) {
                return PitchforkBadge(
                    year: year,
                    rank: entry.rank,
                    coverURL: entry.albumCover
                )
            }
        }
        
        return nil
    }
    
    /// Get all badges for an artist (useful for artist view)
    func getAllBadges(for artist: String) async -> [PitchforkBadge] {
        guard let yearEndData = try? await fetchYearEndListData(for: artist) else {
            return []
        }
        
        return yearEndData.entries.map { year, entry in
            PitchforkBadge(
                year: year,
                rank: entry.rank,
                coverURL: entry.albumCover
            )
        }.sorted { $0.year > $1.year } // Sort by year descending
    }
    
    // MARK: - Helper Methods
    
    /// Compare album titles with fuzzy matching
    private func albumTitlesMatch(_ title1: String, _ title2: String) -> Bool {
        let normalized1 = normalizeAlbumTitle(title1)
        let normalized2 = normalizeAlbumTitle(title2)
        
        // Exact match
        if normalized1 == normalized2 {
            return true
        }
        
        // Contains match (for cases like "Abbey Road (Remastered)" vs "Abbey Road")
        if normalized1.contains(normalized2) || normalized2.contains(normalized1) {
            return true
        }
        
        return false
    }
    
    /// Normalize album title for comparison
    private func normalizeAlbumTitle(_ title: String) -> String {
        return title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
    
    /// Clear cache (useful for testing or settings)
    func clearCache() {
        cache.removeAllObjects()
        print("🗑️ [Pitchfork] Cache cleared")
    }
}
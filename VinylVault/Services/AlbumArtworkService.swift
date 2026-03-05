//
//  AlbumArtworkService.swift
//  VinylVault
//
//  Service for fetching album artwork from multiple sources
//

import Foundation

struct iTunesSearchResult: Codable {
    let resultCount: Int
    let results: [iTunesAlbum]
}

struct iTunesAlbum: Codable {
    let artworkUrl100: String?
    let artworkUrl60: String?
    
    var highResArtwork: String? {
        // iTunes allows requesting higher resolution by replacing the size in URL
        // e.g., artworkUrl100 -> artworkUrl600
        return artworkUrl100?.replacingOccurrences(of: "100x100", with: "600x600")
    }
}

enum AlbumArtworkError: Error {
    case noArtworkFound
    case invalidURL
    case networkError(Error)
}

class AlbumArtworkService {
    static let shared = AlbumArtworkService()
    
    private init() {}
    
    // MARK: - Fetch Album Artwork
    
    /// Attempts to fetch album artwork from multiple sources with fallback
    func fetchAlbumArtwork(artist: String, album: String) async throws -> String {
        // Try iTunes/Apple Music first (best coverage and quality)
        if let artworkURL = try? await fetchFromiTunes(artist: artist, album: album) {
            return artworkURL
        }
        
        // If iTunes fails, try MusicBrainz + Cover Art Archive
        if let artworkURL = try? await fetchFromMusicBrainz(artist: artist, album: album) {
            return artworkURL
        }
        
        // If all sources fail, throw error
        throw AlbumArtworkError.noArtworkFound
    }
    
    // MARK: - iTunes/Apple Music API
    
    private func fetchFromiTunes(artist: String, album: String) async throws -> String {
        let baseURL = "https://itunes.apple.com/search"
        var components = URLComponents(string: baseURL)
        
        // Combine artist and album for better search results
        let searchTerm = "\(artist) \(album)"
        
        components?.queryItems = [
            URLQueryItem(name: "term", value: searchTerm),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "5")
        ]
        
        guard let url = components?.url else {
            throw AlbumArtworkError.invalidURL
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw AlbumArtworkError.noArtworkFound
            }
            
            let result = try JSONDecoder().decode(iTunesSearchResult.self, from: data)
            
            // Return the first result's high-res artwork
            if let firstResult = result.results.first,
               let artworkURL = firstResult.highResArtwork {
                return artworkURL
            }
            
            throw AlbumArtworkError.noArtworkFound
        } catch {
            throw AlbumArtworkError.networkError(error)
        }
    }
    
    // MARK: - MusicBrainz + Cover Art Archive
    
    private func fetchFromMusicBrainz(artist: String, album: String) async throws -> String {
        // First, search MusicBrainz for the release
        let searchURL = "https://musicbrainz.org/ws/2/release/"
        var components = URLComponents(string: searchURL)
        
        let query = "artist:\(artist) AND release:\(album)"
        
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5")  // Try multiple releases
        ]
        
        guard let url = components?.url else {
            throw AlbumArtworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("VinylVault/1.0 (contact@vinylvault.app)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw AlbumArtworkError.noArtworkFound
            }
            
            // Parse MusicBrainz response to get release IDs
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let releases = json["releases"] as? [[String: Any]] {
                
                // Try each release until we find cover art
                for release in releases {
                    if let releaseId = release["id"] as? String {
                        // Try multiple image sizes in order of preference
                        let imageSizes = ["1200", "500", "250", ""]  // Empty string tries default
                        
                        for size in imageSizes {
                            let sizeParam = size.isEmpty ? "" : "-\(size)"
                            let coverArtURL = "https://coverartarchive.org/release/\(releaseId)/front\(sizeParam)"
                            
                            // Check if the cover art exists
                            if let artworkURL = URL(string: coverArtURL) {
                                var headRequest = URLRequest(url: artworkURL)
                                headRequest.httpMethod = "HEAD"
                                headRequest.timeoutInterval = 5
                                
                                do {
                                    let (_, headResponse) = try await URLSession.shared.data(for: headRequest)
                                    
                                    if let httpHeadResponse = headResponse as? HTTPURLResponse,
                                       httpHeadResponse.statusCode == 200 {
                                        return coverArtURL
                                    }
                                } catch {
                                    // Continue to next size/release
                                    continue
                                }
                            }
                        }
                    }
                }
            }
            
            throw AlbumArtworkError.noArtworkFound
        } catch {
            throw AlbumArtworkError.networkError(error)
        }
    }
    
    // MARK: - Helper: Get High Resolution URL
    
    /// Converts a low-res artwork URL to high-res if possible
    func getHighResolutionURL(from url: String) -> String {
        // iTunes URLs can be upgraded
        if url.contains("mzstatic.com") {
            return url.replacingOccurrences(of: "100x100", with: "600x600")
                      .replacingOccurrences(of: "200x200", with: "600x600")
        }
        
        // Cover Art Archive URLs can specify size
        if url.contains("coverartarchive.org") && url.contains("-250") {
            return url.replacingOccurrences(of: "-250", with: "-500")
        }
        
        return url
    }
}
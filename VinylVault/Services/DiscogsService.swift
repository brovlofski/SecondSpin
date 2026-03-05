//
//  DiscogsService.swift
//  VinylVault
//
//  Service for Discogs API integration
//

import Foundation

struct DiscogsSearchResult: Codable {
    let results: [DiscogsRelease]
}

struct DiscogsRelease: Codable, Identifiable {
    let id: Int
    let title: String
    let year: String?
    let thumb: String?
    let coverImage: String?
    let resourceUrl: String?
    let format: [String]?
    let label: [String]?
    let genre: [String]?
    let style: [String]?
    let country: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, year, thumb, format, label, genre, style, country
        case coverImage = "cover_image"
        case resourceUrl = "resource_url"
    }
}

struct DiscogsReleaseDetail: Codable {
    let id: Int
    let title: String
    let year: Int?
    let artists: [DiscogsArtist]
    let labels: [DiscogsLabel]
    let genres: [String]?
    let styles: [String]?
    let formats: [DiscogsFormat]?
    let tracklist: [DiscogsTrack]?
    let images: [DiscogsImage]?
    let identifiers: [DiscogsIdentifier]?
    let country: String?
    
    struct DiscogsArtist: Codable {
        let name: String
    }
    
    struct DiscogsLabel: Codable {
        let name: String
        let catno: String?
    }
    
    struct DiscogsFormat: Codable {
        let name: String
        let qty: String?
        let descriptions: [String]?
    }
    
    struct DiscogsTrack: Codable {
        let position: String
        let title: String
        let duration: String?
    }
    
    struct DiscogsImage: Codable {
        let type: String
        let uri: String
        let uri150: String?
        
        enum CodingKeys: String, CodingKey {
            case type, uri
            case uri150 = "uri150"
        }
    }
    
    struct DiscogsIdentifier: Codable {
        let type: String
        let value: String
    }
}

enum DiscogsError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case noResults
    case rateLimitExceeded
}

class DiscogsService {
    static let shared = DiscogsService()
    
    private let baseURL = "https://api.discogs.com"
    private let token = "ChNuGIHFtQvJKLkvcQQCEgcdDSVfXvKcVrxQASKO"
    
    private init() {}
    
    // MARK: - Search by Barcode
    
    func searchByBarcode(_ barcode: String) async throws -> [DiscogsRelease] {
        let endpoint = "\(baseURL)/database/search"
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "barcode", value: barcode),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "token", value: token)
        ]
        
        guard let url = components?.url else {
            throw DiscogsError.invalidURL
        }
        
        return try await performSearch(url: url)
    }
    
    // MARK: - Keyword Search

    func searchByKeyword(_ query: String) async throws -> [DiscogsRelease] {
        let endpoint = "\(baseURL)/database/search"
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "token", value: token)
        ]

        guard let url = components?.url else {
            throw DiscogsError.invalidURL
        }

        return try await performSearch(url: url)
    }

    // MARK: - Search by Artist and Title
    
    func searchByArtistAndTitle(
        artist: String,
        title: String,
        format: String? = nil,
        country: String? = nil
    ) async throws -> [DiscogsRelease] {
        let endpoint = "\(baseURL)/database/search"
        var components = URLComponents(string: endpoint)
        
        var queryItems = [
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "release_title", value: title),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "token", value: token)
        ]
        
        if let format = format, !format.isEmpty {
            queryItems.append(URLQueryItem(name: "format", value: format))
        }
        
        if let country = country, !country.isEmpty {
            queryItems.append(URLQueryItem(name: "country", value: country))
        }
        
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw DiscogsError.invalidURL
        }
        
        return try await performSearch(url: url)
    }
    
    // MARK: - Get Release Details
    
    func getReleaseDetails(releaseId: Int) async throws -> DiscogsReleaseDetail {
        let endpoint = "\(baseURL)/releases/\(releaseId)"
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "token", value: token)
        ]
        
        guard let url = components?.url else {
            throw DiscogsError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("VinylVault/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DiscogsError.invalidResponse
            }
            
            if httpResponse.statusCode == 429 {
                throw DiscogsError.rateLimitExceeded
            }
            
            guard httpResponse.statusCode == 200 else {
                throw DiscogsError.invalidResponse
            }
            
            let detail = try JSONDecoder().decode(DiscogsReleaseDetail.self, from: data)
            return detail
        } catch let error as DiscogsError {
            throw error
        } catch let error as DecodingError {
            throw DiscogsError.decodingError(error)
        } catch {
            throw DiscogsError.networkError(error)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func performSearch(url: URL) async throws -> [DiscogsRelease] {
        var request = URLRequest(url: url)
        request.setValue("VinylVault/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DiscogsError.invalidResponse
            }
            
            if httpResponse.statusCode == 429 {
                throw DiscogsError.rateLimitExceeded
            }
            
            guard httpResponse.statusCode == 200 else {
                throw DiscogsError.invalidResponse
            }
            
            let searchResult = try JSONDecoder().decode(DiscogsSearchResult.self, from: data)
            
            if searchResult.results.isEmpty {
                throw DiscogsError.noResults
            }
            
            return searchResult.results
        } catch let error as DiscogsError {
            throw error
        } catch let error as DecodingError {
            throw DiscogsError.decodingError(error)
        } catch {
            throw DiscogsError.networkError(error)
        }
    }
}
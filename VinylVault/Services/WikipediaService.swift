//
//  WikipediaService.swift
//  VinylVault
//
//  Service for Wikipedia API integration
//

import Foundation

struct WikipediaResponse: Codable {
    let query: WikipediaQuery?
    
    struct WikipediaQuery: Codable {
        let pages: [String: WikipediaPage]
    }
    
    struct WikipediaPage: Codable {
        let pageid: Int?
        let title: String
        let extract: String?
        let fullurl: String?
    }
}

enum WikipediaError: Error {
    case invalidURL
    case noResults
    case networkError(Error)
    case decodingError(Error)
}

class WikipediaService {
    static let shared = WikipediaService()
    
    private let baseURL = "https://en.wikipedia.org/w/api.php"
    
    private init() {}
    
    // MARK: - Fetch Album Description

    func fetchAlbumDescription(albumTitle: String, artist: String) async throws -> String {
        guard let page = await fetchPage(albumTitle: albumTitle, artist: artist),
              let extract = page.extract else {
            throw WikipediaError.noResults
        }
        return extract
    }

    // MARK: - Fetch Album Page URL

    func fetchAlbumPageURL(albumTitle: String, artist: String) async -> URL? {
        guard let page = await fetchPage(albumTitle: albumTitle, artist: artist) else {
            return nil
        }
        // Prefer fullurl returned by API, fall back to constructing from title
        if let fullurl = page.fullurl, let url = URL(string: fullurl) {
            return url
        }
        let encoded = page.title
            .addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? ""
        return URL(string: "https://en.wikipedia.org/wiki/\(encoded)")
    }

    // MARK: - Internal page fetch

    private func fetchPage(albumTitle: String, artist: String) async -> WikipediaResponse.WikipediaPage? {
        for query in ["\(albumTitle) \(artist)", albumTitle] {
            if let page = try? await performFetch(query: query) {
                return page
            }
        }
        return nil
    }
    
    // MARK: - Private Helper Methods

    private func performFetch(query: String) async throws -> WikipediaResponse.WikipediaPage {
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts|info"),
            URLQueryItem(name: "inprop", value: "url"),
            URLQueryItem(name: "exintro", value: "true"),
            URLQueryItem(name: "explaintext", value: "true"),
            URLQueryItem(name: "titles", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "redirects", value: "1")
        ]

        guard let url = components?.url else {
            throw WikipediaError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(WikipediaResponse.self, from: data)

            guard let pages = response.query?.pages,
                  let page = pages.values.first,
                  let extract = page.extract,
                  page.pageid != nil,
                  !extract.isEmpty else {
                throw WikipediaError.noResults
            }

            return page
        } catch let error as WikipediaError {
            throw error
        } catch let error as DecodingError {
            throw WikipediaError.decodingError(error)
        } catch {
            throw WikipediaError.networkError(error)
        }
    }
}
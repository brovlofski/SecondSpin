//
//  WikipediaService.swift
//  VinylVault
//
//  Enhanced Wikipedia integration with Wikidata album validation.
//  Pipeline: search → score → fetch Wikidata ID → validate P31 (instance of album)
//            → fetch extract → cache result
//

import Foundation

// MARK: - Public result type

struct WikipediaAlbumResult {
    let pageTitle: String
    let wikidataID: String?
    let extract: String
    let pageURL: URL?
}

// MARK: - Error

enum WikipediaError: Error {
    case invalidURL
    case noResults
    case networkError(Error)
    case decodingError(Error)
}

// MARK: - Private API response models

private struct WPSearchResponse: Decodable {
    let query: Query?
    struct Query: Decodable {
        let search: [Hit]
    }
    struct Hit: Decodable {
        let title: String
        let pageid: Int
    }
}

private struct WPPagePropsResponse: Decodable {
    let query: Query?
    struct Query: Decodable {
        let pages: [String: Page]
    }
    struct Page: Decodable {
        let pageid: Int?
        let title: String
        let pageprops: Props?
    }
    struct Props: Decodable {
        let wikibaseItem: String?
        enum CodingKeys: String, CodingKey {
            case wikibaseItem = "wikibase_item"
        }
    }
}

private struct WPExtractResponse: Decodable {
    let query: Query?
    struct Query: Decodable {
        let pages: [String: Page]
    }
    struct Page: Decodable {
        let pageid: Int?
        let title: String
        let extract: String?
        let fullurl: String?
    }
}

private struct WikidataEntityResponse: Decodable {
    let entities: [String: Entity]

    struct Entity: Decodable {
        let claims: [String: [Claim]]?
    }

    struct Claim: Decodable {
        let mainsnak: Mainsnak
    }

    struct Mainsnak: Decodable {
        let datavalue: DataValue?
    }

    struct DataValue: Decodable {
        let value: EntityValue?
        let type: String?
    }

    // Wikidata entity values are dicts; plain string values are ignored here
    struct EntityValue: Decodable {
        let id: String? // e.g. "Q482994"
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            id = try? c?.decode(String.self, forKey: .id)
        }
        enum CodingKeys: String, CodingKey { case id }
    }
}

// MARK: - Service

class WikipediaService {
    static let shared = WikipediaService()

    private let wpBase    = "https://en.wikipedia.org/w/api.php"
    private let wdBase    = "https://www.wikidata.org/wiki/Special:EntityData"

    // Wikidata Q-IDs that represent music-album types (P31 values)
    private let albumQIDs: Set<String> = [
        "Q482994",    // album
        "Q208569",    // studio album
        "Q209939",    // compilation album
        "Q1194816",   // live album
        "Q169930",    // EP
        "Q189553",    // soundtrack album
        "Q105543609", // music album (broader)
        "Q3983927",   // demo album
        "Q220898",    // box set
        "Q592156",    // mixtape
        "Q1542673",   // single
    ]

    // In-memory cache keyed by "lowercasedTitle|lowercasedArtist"
    private var cache: [String: WikipediaAlbumResult] = [:]
    private let cacheQueue = DispatchQueue(label: "wiki.cache", attributes: .concurrent)

    private init() {}

    // MARK: - Public API (backward compatible + optional year)

    func fetchAlbumDescription(albumTitle: String, artist: String, year: Int? = nil) async throws -> String {
        let result = try await resolveValidatedPage(albumTitle: albumTitle, artist: artist, year: year)
        return result.extract
    }

    func fetchAlbumPageURL(albumTitle: String, artist: String, year: Int? = nil) async -> URL? {
        return try? await resolveValidatedPage(albumTitle: albumTitle, artist: artist, year: year).pageURL
    }

    // MARK: - Pipeline

    private func resolveValidatedPage(albumTitle: String, artist: String, year: Int?) async throws -> WikipediaAlbumResult {
        let key = "\(albumTitle.lowercased())|\(artist.lowercased())"
        if let cached = cacheQueue.sync(execute: { cache[key] }) { return cached }

        // Prioritised query list (Steps 1 & 9)
        var queries: [String] = [
            "\(albumTitle) \(artist) album",
            "\(albumTitle) \(artist)",
        ]
        if let y = year, y > 0 {
            queries.append("\(albumTitle) \(y) album")
        }
        queries.append("\(albumTitle) album")
        queries.append(albumTitle)

        for query in queries {
            if let result = try? await tryQuery(query, albumTitle: albumTitle, artist: artist) {
                cacheQueue.async(flags: .barrier) { [weak self] in self?.cache[key] = result }
                return result
            }
        }

        throw WikipediaError.noResults
    }

    /// Search → score → validate top candidates
    private func tryQuery(_ query: String, albumTitle: String, artist: String) async throws -> WikipediaAlbumResult {
        let hits = try await searchWikipedia(query: query)
        guard !hits.isEmpty else { throw WikipediaError.noResults }

        // Score and sort (Step 3)
        let ranked = hits
            .map { ($0, score(hit: $0, albumTitle: albumTitle, artist: artist)) }
            .sorted { $0.1 > $1.1 }

        // Try top-3 candidates (Step 4 onward)
        for (hit, _) in ranked.prefix(3) {
            if let result = try? await validateAndFetch(pageTitle: hit.title, artist: artist) {
                return result
            }
        }

        throw WikipediaError.noResults
    }

    // MARK: - Scoring heuristics (Step 3)

    private func score(hit: WPSearchResponse.Hit, albumTitle: String, artist: String) -> Int {
        var s = 0
        let t = hit.title.lowercased()
        let normArtist = artist.lowercased()
        let normTitle  = albumTitle.lowercased()

        // Positive: article is obviously an album page
        if t.contains("(album)")      { s += 10 }
        if t.contains("(ep)")         { s += 8  }
        if t.contains("(soundtrack)") { s += 6  }
        if t.contains("(single)")     { s += 3  }

        // Positive: artist tokens appear in the candidate title
        let artistTokens = normArtist.components(separatedBy: .whitespaces).filter { $0.count > 2 }
        for token in artistTokens where t.contains(token) { s += 3 }

        // Positive: album title match
        if t.hasPrefix(normTitle) { s += 5 }
        if t == normTitle          { s += 4 }

        // Negative: clearly wrong type
        if t.contains("disambiguation") { s -= 20 }
        if t.contains("(film)")  || t.contains("(movie)")    { s -= 15 }
        if t.contains("(book)")  || t.contains("(novel)")    { s -= 15 }
        if t.contains("(tv ")    || t.contains("television") { s -= 10 }
        if t.contains("(series)")                            { s -= 10 }

        return s
    }

    // MARK: - Validate a candidate page (Steps 4–6)

    private func validateAndFetch(pageTitle: String, artist: String) async throws -> WikipediaAlbumResult {
        // Step 4: get Wikidata entity ID
        if let wikidataID = try? await fetchWikidataID(pageTitle: pageTitle) {
            // Step 5: validate via Wikidata
            let valid = await validateWikidata(wikidataID: wikidataID)
            guard valid else { throw WikipediaError.noResults }

            // Step 6: fetch extract
            return try await fetchExtract(pageTitle: pageTitle, wikidataID: wikidataID)
        }

        // No Wikidata link: accept only if the title itself signals it's an album
        let tl = pageTitle.lowercased()
        let looksLikeAlbum = tl.contains("(album)") || tl.contains("(ep)") ||
                             tl.contains("(soundtrack)") || tl.contains("(single)")
        guard looksLikeAlbum else { throw WikipediaError.noResults }

        return try await fetchExtract(pageTitle: pageTitle, wikidataID: nil)
    }

    // MARK: - Step 2: Wikipedia search

    private func searchWikipedia(query: String) async throws -> [WPSearchResponse.Hit] {
        var c = URLComponents(string: wpBase)
        c?.queryItems = [
            URLQueryItem(name: "action",      value: "query"),
            URLQueryItem(name: "list",        value: "search"),
            URLQueryItem(name: "srsearch",    value: query),
            URLQueryItem(name: "srnamespace", value: "0"),
            URLQueryItem(name: "srlimit",     value: "5"),
            URLQueryItem(name: "format",      value: "json"),
            URLQueryItem(name: "origin",      value: "*"),
        ]
        guard let url = c?.url else { throw WikipediaError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(WPSearchResponse.self, from: data)
        return resp.query?.search ?? []
    }

    // MARK: - Step 4: Fetch Wikidata entity ID

    private func fetchWikidataID(pageTitle: String) async throws -> String {
        var c = URLComponents(string: wpBase)
        c?.queryItems = [
            URLQueryItem(name: "action",    value: "query"),
            URLQueryItem(name: "prop",      value: "pageprops"),
            URLQueryItem(name: "titles",    value: pageTitle),
            URLQueryItem(name: "format",    value: "json"),
            URLQueryItem(name: "redirects", value: "1"),
        ]
        guard let url = c?.url else { throw WikipediaError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(WPPagePropsResponse.self, from: data)

        guard let page = resp.query?.pages.values.first,
              let wdID = page.pageprops?.wikibaseItem else {
            throw WikipediaError.noResults
        }
        return wdID
    }

    // MARK: - Step 5: Wikidata P31 validation

    private func validateWikidata(wikidataID: String) async -> Bool {
        guard let url = URL(string: "\(wdBase)/\(wikidataID).json") else { return false }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return false }
        guard let resp = try? JSONDecoder().decode(WikidataEntityResponse.self, from: data) else { return false }
        guard let entity = resp.entities[wikidataID] else { return false }

        // P31 = instance of — must match a music-album QID
        guard let p31Claims = entity.claims?["P31"] else { return false }
        return p31Claims.contains { claim in
            guard let qid = claim.mainsnak.datavalue?.value?.id else { return false }
            return albumQIDs.contains(qid)
        }
    }

    // MARK: - Step 6: Fetch Wikipedia extract

    private func fetchExtract(pageTitle: String, wikidataID: String?) async throws -> WikipediaAlbumResult {
        var c = URLComponents(string: wpBase)
        c?.queryItems = [
            URLQueryItem(name: "action",      value: "query"),
            URLQueryItem(name: "prop",        value: "extracts|info"),
            URLQueryItem(name: "inprop",      value: "url"),
            URLQueryItem(name: "exintro",     value: "true"),
            URLQueryItem(name: "explaintext", value: "true"),
            URLQueryItem(name: "titles",      value: pageTitle),
            URLQueryItem(name: "format",      value: "json"),
            URLQueryItem(name: "redirects",   value: "1"),
        ]
        guard let url = c?.url else { throw WikipediaError.invalidURL }

        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(WPExtractResponse.self, from: data)

        guard let page = resp.query?.pages.values.first,
              let extract = page.extract,
              page.pageid != nil,
              !extract.isEmpty else {
            throw WikipediaError.noResults
        }

        let pageURL: URL?
        if let fullurl = page.fullurl {
            pageURL = URL(string: fullurl)
        } else {
            let encoded = page.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            pageURL = URL(string: "https://en.wikipedia.org/wiki/\(encoded)")
        }

        return WikipediaAlbumResult(
            pageTitle: page.title,
            wikidataID: wikidataID,
            extract: extract,
            pageURL: pageURL
        )
    }
}
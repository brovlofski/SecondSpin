//
//  WikipediaService.swift
//  VinylVault
//
//  Wikipedia album resolution with Wikidata validation.
//
//  Resolution pipeline:
//    Phase 1 – Predicted titles (fast, no search query):
//      1. Generate 3 candidate page titles using common Wikipedia album naming patterns.
//      2. Check each page exists via action=query&titles=.
//      3. Validate via Wikidata (P31 instance-of, P1476 title, P175 performer).
//      4. If any passes → fetch extract and return immediately.
//    Phase 2 – Fallback search (only runs if Phase 1 fails):
//      5. Search Wikipedia with "<title> <artist> album" (limit 10).
//      6. Rank hits, validate top-3 via same Wikidata checks.
//      7. Return first valid result.
//

import Foundation

// MARK: - Public result

struct WikipediaAlbumResult {
    let pageTitle: String
    let wikidataID: String?
    let extract: String
    let pageURL: URL?
}

// MARK: - Errors

enum WikipediaError: Error {
    case invalidURL
    case noResults
    case networkError(Error)
    case decodingError(Error)
}

// MARK: - Wikipedia response models

private struct WPSearchResponse: Decodable {
    let query: Query?
    struct Query: Decodable { let search: [Hit] }
    struct Hit: Decodable { let title: String; let pageid: Int }
}

private struct WPPagePropsResponse: Decodable {
    let query: Query?
    struct Query: Decodable { let pages: [String: Page] }
    struct Page: Decodable {
        let pageid: Int?
        let title: String
        let pageprops: Props?
        struct Props: Decodable {
            let wikibaseItem: String?
            enum CodingKeys: String, CodingKey { case wikibaseItem = "wikibase_item" }
        }
    }
}

private struct WPExtractResponse: Decodable {
    let query: Query?
    struct Query: Decodable { let pages: [String: Page] }
    struct Page: Decodable {
        let pageid: Int?
        let title: String
        let extract: String?
        let fullurl: String?
    }
}

// MARK: - Wikidata models (wbgetentities API)

private struct WDGetEntitiesResponse: Decodable {
    let entities: [String: WDEntity]
}

private struct WDEntity: Decodable {
    let id: String?
    let labels: [String: WDLabel]?
    let claims: [String: [WDClaim]]?
    var englishLabel: String? { labels?["en"]?.value }
}

private struct WDLabel: Decodable {
    let language: String
    let value: String
}

private struct WDClaim: Decodable {
    let mainsnak: WDMainsnak
}

private struct WDMainsnak: Decodable {
    let datavalue: WDDataValue?
}

private struct WDDataValue: Decodable {
    let type: String?
    let value: WDValue?
}

/// Handles both `wikibase-entityid` (has `id`) and `monolingualtext` (has `text`+`language`).
private struct WDValue: Decodable {
    let id: String?
    let text: String?
    let language: String?

    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        id       = try? c?.decode(String.self, forKey: .id)
        text     = try? c?.decode(String.self, forKey: .text)
        language = try? c?.decode(String.self, forKey: .language)
    }
    enum CodingKeys: String, CodingKey { case id, text, language }
}

// MARK: - Service

class WikipediaService {
    static let shared = WikipediaService()

    private let wpBase = "https://en.wikipedia.org/w/api.php"
    private let wdAPI  = "https://www.wikidata.org/w/api.php"

    /// Wikidata Q-IDs accepted for P31 (instance of)
    private let albumQIDs: Set<String> = [
        "Q482994",    // album
        "Q208569",    // studio album
        "Q209939",    // compilation album
        "Q1194816",   // live album
        "Q169930",    // EP
        "Q189553",    // soundtrack album
        "Q105543609", // music album
        "Q3983927",   // demo album
        "Q220898",    // box set
        "Q592156",    // mixtape
        "Q1542673",   // single
    ]

    private var cache: [String: WikipediaAlbumResult] = [:]
    private let cacheQueue = DispatchQueue(label: "wiki.cache", attributes: .concurrent)

    private init() {}
    
    /// Clear the Wikipedia cache. Call this from Settings or when needed.
    func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }

    // MARK: - Public API (backward compatible)

    func fetchAlbumDescription(albumTitle: String, artist: String, year: Int? = nil) async throws -> String {
        try await resolveValidatedPage(albumTitle: albumTitle, artist: artist, year: year).extract
    }

    func fetchAlbumPageURL(albumTitle: String, artist: String, year: Int? = nil) async -> URL? {
        try? await resolveValidatedPage(albumTitle: albumTitle, artist: artist, year: year).pageURL
    }

    // MARK: - Main pipeline

    private func resolveValidatedPage(albumTitle: String, artist: String, year: Int?) async throws -> WikipediaAlbumResult {
        let key = "\(albumTitle.lowercased())|\(artist.lowercased())"
        if let cached = cacheQueue.sync(execute: { cache[key] }) { return cached }

        // ── Phase 1: Try predicted page titles ──────────────────────────────────
        for predicted in predictedTitles(albumTitle: albumTitle, artist: artist) {
            guard await checkPageExists(predicted) else { continue }
            if let result = try? await validateAndFetch(pageTitle: predicted,
                                                        albumTitle: albumTitle,
                                                        artist: artist) {
                store(result, key: key); return result
            }
        }

        // ── Phase 2: Fallback to Wikipedia search ────────────────────────────────
        let queries: [String] = [
            "\(albumTitle) \(artist) album",
            "\(albumTitle) \(artist)",
            "\(albumTitle) album",
        ]
        for query in queries {
            if let result = try? await searchAndValidate(query: query,
                                                         albumTitle: albumTitle,
                                                         artist: artist) {
                store(result, key: key); return result
            }
        }

        throw WikipediaError.noResults
    }

    // MARK: - Phase 1: Predicted title generation

    /// Returns candidate page titles in priority order.
    private func predictedTitles(albumTitle: String, artist: String) -> [String] {
        [
            "\(albumTitle) (\(artist) album)",   // "Music (Madonna album)"
            "\(albumTitle) (album)",              // "Rumours (album)"
            albumTitle,                           // "Nevermind"
        ]
    }

    // MARK: - Phase 1: Page existence check

    /// Returns true when Wikipedia has a non-missing page for `title`.
    private func checkPageExists(_ title: String) async -> Bool {
        var c = URLComponents(string: wpBase)
        c?.queryItems = [
            URLQueryItem(name: "action",    value: "query"),
            URLQueryItem(name: "titles",    value: title),
            URLQueryItem(name: "format",    value: "json"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "origin",    value: "*"),
        ]
        guard let url = c?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(WPPagePropsResponse.self, from: data),
              let page = resp.query?.pages.values.first else { return false }
        // Wikipedia marks missing pages with pageid = nil or negative key in the dict
        return (page.pageid ?? -1) > 0
    }

    // MARK: - Phase 2: Search + validate

    private func searchAndValidate(query: String, albumTitle: String, artist: String) async throws -> WikipediaAlbumResult {
        let hits = try await searchWikipedia(query: query, limit: 10)
        guard !hits.isEmpty else { throw WikipediaError.noResults }

        let ranked = hits
            .map { ($0, score(title: $0.title, albumTitle: albumTitle, artist: artist)) }
            .sorted { $0.1 > $1.1 }

        for (hit, _) in ranked.prefix(3) {
            if let result = try? await validateAndFetch(pageTitle: hit.title,
                                                        albumTitle: albumTitle,
                                                        artist: artist) {
                return result
            }
        }
        throw WikipediaError.noResults
    }

    // MARK: - Validation + fetch

    /// Resolves a Wikidata entity for `pageTitle`, applies P31/P1476/P175 checks, then fetches extract.
    private func validateAndFetch(pageTitle: String, albumTitle: String, artist: String) async throws -> WikipediaAlbumResult {
        // 1. Get Wikidata entity ID from Wikipedia page props
        let wikidataID = try? await fetchWikidataID(pageTitle: pageTitle)

        if let wdID = wikidataID {
            // 2. Fetch full Wikidata entity (labels + claims)
            if let entity = await fetchWikidataEntity(qid: wdID) {
                // 3. P31: must be an album type
                guard isAlbum(entity: entity) else { throw WikipediaError.noResults }

                // 4. P1476: album title similarity ≥ 90% (soft – skip if property absent)
                if let wdTitle = wikidataAlbumTitle(entity: entity) {
                    guard charSimilarity(normalize(wdTitle), normalize(albumTitle)) >= 0.85 else {
                        throw WikipediaError.noResults
                    }
                }

                // 5. P175: performer fuzzy match (soft – skip if property absent)
                let performerQIDs = performerIDs(entity: entity)
                if !performerQIDs.isEmpty {
                    let matched = await anyPerformerMatches(qids: performerQIDs, artist: artist)
                    guard matched else { throw WikipediaError.noResults }
                }
            } else {
                // Wikidata fetch failed: fall back to title heuristic
                let tl = pageTitle.lowercased()
                guard tl.contains("(album)") || tl.contains("(ep)") ||
                      tl.contains("(soundtrack)") || tl.contains("(single)") else {
                    throw WikipediaError.noResults
                }
            }
        } else {
            // No Wikidata link: only accept if the page title is clearly an album
            let tl = pageTitle.lowercased()
            guard tl.contains("(album)") || tl.contains("(ep)") ||
                  tl.contains("(soundtrack)") || tl.contains("(single)") else {
                throw WikipediaError.noResults
            }
        }

        return try await fetchExtract(pageTitle: pageTitle, wikidataID: wikidataID)
    }

    // MARK: - Wikidata helpers

    /// Fetches the `wikibase_item` from Wikipedia page props.
    private func fetchWikidataID(pageTitle: String) async throws -> String {
        var c = URLComponents(string: wpBase)
        c?.queryItems = [
            URLQueryItem(name: "action",    value: "query"),
            URLQueryItem(name: "prop",      value: "pageprops"),
            URLQueryItem(name: "titles",    value: pageTitle),
            URLQueryItem(name: "format",    value: "json"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "origin",    value: "*"),
        ]
        guard let url = c?.url else { throw WikipediaError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(WPPagePropsResponse.self, from: data)
        guard let wdID = resp.query?.pages.values.first?.pageprops?.wikibaseItem else {
            throw WikipediaError.noResults
        }
        return wdID
    }

    /// Fetches a Wikidata entity's labels and claims via `wbgetentities`.
    private func fetchWikidataEntity(qid: String) async -> WDEntity? {
        var c = URLComponents(string: wdAPI)
        c?.queryItems = [
            URLQueryItem(name: "action",    value: "wbgetentities"),
            URLQueryItem(name: "ids",       value: qid),
            URLQueryItem(name: "props",     value: "labels|claims"),
            URLQueryItem(name: "languages", value: "en"),
            URLQueryItem(name: "format",    value: "json"),
            URLQueryItem(name: "origin",    value: "*"),
        ]
        guard let url = c?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(WDGetEntitiesResponse.self, from: data) else {
            return nil
        }
        return resp.entities[qid]
    }

    /// Fetches the English label of a Wikidata entity (used for performer lookup).
    private func fetchWikidataLabel(qid: String) async -> String? {
        await fetchWikidataEntity(qid: qid)?.englishLabel
    }

    // MARK: - Wikidata claim extractors

    private func isAlbum(entity: WDEntity) -> Bool {
        guard let p31 = entity.claims?["P31"] else { return false }
        return p31.contains { albumQIDs.contains($0.mainsnak.datavalue?.value?.id ?? "") }
    }

    /// Returns the English album title from P1476 (monolingual text).
    private func wikidataAlbumTitle(entity: WDEntity) -> String? {
        guard let p1476 = entity.claims?["P1476"] else { return nil }
        for claim in p1476 {
            if let v = claim.mainsnak.datavalue?.value,
               (v.language == "en" || v.language == nil),
               let text = v.text { return text }
        }
        return p1476.first?.mainsnak.datavalue?.value?.text
    }

    /// Returns performer (P175) QIDs.
    private func performerIDs(entity: WDEntity) -> [String] {
        (entity.claims?["P175"] ?? []).compactMap { $0.mainsnak.datavalue?.value?.id }
    }

    /// Returns true if any performer QID's English label fuzzy-matches `artist`.
    private func anyPerformerMatches(qids: [String], artist: String) async -> Bool {
        let normArtist = normalize(artist)
        for qid in qids {
            if let label = await fetchWikidataLabel(qid: qid) {
                if charSimilarity(normalize(label), normArtist) >= 0.70 { return true }
            }
        }
        return false
    }

    // MARK: - Wikipedia search

    private func searchWikipedia(query: String, limit: Int = 10) async throws -> [WPSearchResponse.Hit] {
        var c = URLComponents(string: wpBase)
        c?.queryItems = [
            URLQueryItem(name: "action",      value: "query"),
            URLQueryItem(name: "list",        value: "search"),
            URLQueryItem(name: "srsearch",    value: query),
            URLQueryItem(name: "srnamespace", value: "0"),
            URLQueryItem(name: "srlimit",     value: "\(limit)"),
            URLQueryItem(name: "format",      value: "json"),
            URLQueryItem(name: "origin",      value: "*"),
        ]
        guard let url = c?.url else { throw WikipediaError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(WPSearchResponse.self, from: data)
        return resp.query?.search ?? []
    }

    // MARK: - Search result scoring heuristic

    private func score(title: String, albumTitle: String, artist: String) -> Int {
        var s = 0
        let t  = title.lowercased()
        let na = artist.lowercased()
        let nt = albumTitle.lowercased()

        if t.contains("(album)")                              { s += 10 }
        if t.contains("(ep)")                                 { s += 8  }
        if t.contains("(soundtrack)")                         { s += 6  }
        if t.contains("(single)")                             { s += 3  }
        for token in na.components(separatedBy: .whitespaces).filter({ $0.count > 2 })
            where t.contains(token)                           { s += 3  }
        if t.hasPrefix(nt)                                    { s += 5  }
        if t == nt                                            { s += 4  }
        if t.contains("disambiguation")                       { s -= 20 }
        if t.contains("(film)") || t.contains("(movie)")     { s -= 15 }
        if t.contains("(book)") || t.contains("(novel)")     { s -= 15 }
        if t.contains("(tv ")   || t.contains("television")  { s -= 10 }
        if t.contains("(series)")                             { s -= 10 }
        return s
    }

    // MARK: - Extract fetch

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
            URLQueryItem(name: "origin",      value: "*"),
        ]
        guard let url = c?.url else { throw WikipediaError.invalidURL }

        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(WPExtractResponse.self, from: data)

        guard let page = resp.query?.pages.values.first,
              let extract = page.extract,
              let pid = page.pageid, pid > 0,
              !extract.isEmpty else {
            throw WikipediaError.noResults
        }

        let pageURL: URL?
        if let full = page.fullurl {
            pageURL = URL(string: full)
        } else {
            let enc = page.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            pageURL = URL(string: "https://en.wikipedia.org/wiki/\(enc)")
        }

        return WikipediaAlbumResult(pageTitle: page.title,
                                    wikidataID: wikidataID,
                                    extract: extract,
                                    pageURL: pageURL)
    }

    // MARK: - String utilities

    /// Normalise: lowercase, strip non-alphanumeric, collapse whitespace.
    private func normalize(_ s: String) -> String {
        s.lowercased()
         .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
         .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Character-level similarity: 1 − (Levenshtein / max_len).  Returns 0…1.
    private func charSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        let la = Array(a), lb = Array(b)
        if la.isEmpty && lb.isEmpty { return 1.0 }
        if la.isEmpty || lb.isEmpty { return 0.0 }
        let dist = levenshtein(la, lb)
        return 1.0 - Double(dist) / Double(max(la.count, lb.count))
    }

    private func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var curr = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                curr[j] = a[i-1] == b[j-1]
                    ? prev[j-1]
                    : 1 + min(prev[j-1], prev[j], curr[j-1])
            }
            prev = curr
        }
        return prev[b.count]
    }

    // MARK: - Cache

    private func store(_ result: WikipediaAlbumResult, key: String) {
        cacheQueue.async(flags: .barrier) { [weak self] in self?.cache[key] = result }
    }
}
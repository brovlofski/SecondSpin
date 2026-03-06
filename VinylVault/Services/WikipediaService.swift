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

struct WikipediaAlbumResult: Codable {
    let pageTitle: String
    let wikidataID: String?
    let extract: String
    let pageURL: URL?
    let reviewScores: [AlbumReviewScore]
}

struct AlbumReviewScore: Codable, Identifiable {
    let id = UUID()
    let source: String
    let rating: String
    
    enum CodingKeys: String, CodingKey {
        case source, rating
    }
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

private struct WPParseResponse: Decodable {
    let parse: ParseContent?
    struct ParseContent: Decodable {
        let title: String
        let pageid: Int
        let wikitext: WikitextContent?
        enum CodingKeys: String, CodingKey {
            case title, pageid, wikitext
        }
    }
    struct WikitextContent: Decodable {
        let content: String
        enum CodingKeys: String, CodingKey {
            case content = "*"
        }
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

    private init() {
        loadCache()
    }
    
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

    func resolveValidatedPage(albumTitle: String, artist: String, year: Int?) async throws -> WikipediaAlbumResult {
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

        // Fetch review scores from wikitext
        let reviewScores = await fetchReviewScores(pageTitle: page.title)

        return WikipediaAlbumResult(pageTitle: page.title,
                                    wikidataID: wikidataID,
                                    extract: extract,
                                    pageURL: pageURL,
                                    reviewScores: reviewScores)
    }
    
    // MARK: - Review score extraction
    
    /// Fetches and parses professional review scores from Wikipedia wikitext
    private func fetchReviewScores(pageTitle: String) async -> [AlbumReviewScore] {
        guard let wikitext = await fetchWikitext(pageTitle: pageTitle) else {
            return []
        }
        return parseReviewScores(from: wikitext)
    }
    
    /// Fetches the raw wikitext for a Wikipedia page
    private func fetchWikitext(pageTitle: String) async -> String? {
        var c = URLComponents(string: wpBase)
        c?.queryItems = [
            URLQueryItem(name: "action",  value: "parse"),
            URLQueryItem(name: "page",    value: pageTitle),
            URLQueryItem(name: "prop",    value: "wikitext"),
            URLQueryItem(name: "format",  value: "json"),
            URLQueryItem(name: "origin",  value: "*"),
        ]
        guard let url = c?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let resp = try? JSONDecoder().decode(WPParseResponse.self, from: data) else {
            return nil
        }
        return resp.parse?.wikitext?.content
    }
    
    /// Parses professional review scores from Wikipedia wikitext
    /// Looks for the "Professional ratings" or "Reception" table with Source/Rating columns
    private func parseReviewScores(from wikitext: String) -> [AlbumReviewScore] {
        var scores: [AlbumReviewScore] = []
        
        // Find the review table section - look for common section headers
        let sectionPatterns = [
            "==\\s*Professional\\s+ratings?\\s*==",
            "==\\s*Critical\\s+reception\\s*==",
            "==\\s*Reception\\s*==",
            "==\\s*Reviews\\s*==",
        ]
        
        var relevantSection: String?
        for pattern in sectionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: wikitext, range: NSRange(wikitext.startIndex..., in: wikitext)) {
                let startIndex = wikitext.index(wikitext.startIndex, offsetBy: match.range.location)
                // Extract from this header to the next == header or end
                if let nextHeaderRange = wikitext.range(of: "\\n==", options: [.regularExpression], range: startIndex..<wikitext.endIndex) {
                    relevantSection = String(wikitext[startIndex..<nextHeaderRange.lowerBound])
                } else {
                    relevantSection = String(wikitext[startIndex...])
                }
                break
            }
        }
        
        guard let section = relevantSection else { return [] }
        
        // Look for various table formats used in Wikipedia
        // Format 1: {{Album ratings}} template
        if let albumRatings = extractAlbumRatingsTemplate(from: section) {
            return albumRatings
        }
        
        // Format 2: {| class="wikitable" style table
        if let tableScores = extractWikitableScores(from: section) {
            return tableScores
        }
        
        return scores
    }
    
    /// Extracts review scores from {{Album ratings}} template
    private func extractAlbumRatingsTemplate(from text: String) -> [AlbumReviewScore]? {
        guard text.contains("{{Album ratings") || text.contains("{{album ratings") else {
            return nil
        }
        
        var scores: [AlbumReviewScore] = []
        
        // Match patterns like: | rev1 = Source | rev1score = Rating
        let pattern = "\\|\\s*rev(\\d+)\\s*=\\s*([^|\\n]+?)\\s*\\|\\s*rev\\1score\\s*=\\s*([^|\\n}]+)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let sourceRange = Range(match.range(at: 2), in: text),
               let ratingRange = Range(match.range(at: 3), in: text) {
                
                var source = String(text[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                var rating = String(text[ratingRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Extract rating value from {{rating|X|5}} BEFORE cleaning templates
                if rating.contains("{{rating") || rating.contains("{{Rating") {
                    if let ratingValue = extractRatingValue(from: rating) {
                        rating = ratingValue
                    }
                }
                
                // Clean up wikitext artifacts
                let cleanSource = cleanWikitext(source)
                let cleanRating = cleanWikitext(rating)
                
                if !cleanSource.isEmpty && !cleanRating.isEmpty {
                    scores.append(AlbumReviewScore(source: cleanSource, rating: cleanRating))
                }
            }
        }
        
        return scores.isEmpty ? nil : scores
    }
    
    /// Extracts numeric value from {{rating|X|5}} or {{Rating|X|5}} templates
    private func extractRatingValue(from text: String) -> String? {
        // Match {{rating|X|5}} or {{Rating|X|Y}}
        let pattern = "\\{\\{[Rr]ating\\|([0-9.]+)\\|([0-9.]+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: text),
              let maxRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        
        let value = String(text[valueRange])
        let max = String(text[maxRange])
        
        // Convert to 10-point scale if it's a 5-star rating
        if max == "5", let val = Double(value) {
            let score = (val / 5.0) * 10.0
            return String(format: "%.1f/10", score).replacingOccurrences(of: ".0/10", with: "/10")
        }
        
        return "\(value)/\(max)"
    }
    
    /// Extracts review scores from {| wikitable format
    private func extractWikitableScores(from text: String) -> [AlbumReviewScore]? {
        guard text.contains("{|") && text.contains("|}") else {
            return nil
        }
        
        var scores: [AlbumReviewScore] = []
        
        // Find table rows (|-) with cells (| or ||)
        let lines = text.components(separatedBy: .newlines)
        var inTable = false
        var currentSource: String?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("{|") {
                inTable = true
                continue
            }
            if trimmed.hasPrefix("|}") {
                inTable = false
                break
            }
            
            if !inTable { continue }
            
            // Skip header rows and formatting rows
            if trimmed.hasPrefix("!") || trimmed.hasPrefix("|-") || trimmed.hasPrefix("|+") {
                currentSource = nil
                continue
            }
            
            // Parse table cells
            if trimmed.hasPrefix("|") {
                let cellContent = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                
                // Handle || separator for multiple cells in one line
                if cellContent.contains("||") {
                    let cells = cellContent.components(separatedBy: "||")
                    if cells.count >= 2 {
                        let source = cleanWikitext(cells[0])
                        let rating = cleanWikitext(cells[1])
                        if !source.isEmpty && !rating.isEmpty &&
                           !source.lowercased().contains("source") &&
                           !source.lowercased().contains("publication") {
                            scores.append(AlbumReviewScore(source: source, rating: rating))
                        }
                    }
                } else {
                    // Single cell - alternate between source and rating
                    if let source = currentSource {
                        let rating = cleanWikitext(cellContent)
                        if !rating.isEmpty {
                            scores.append(AlbumReviewScore(source: source, rating: rating))
                        }
                        currentSource = nil
                    } else {
                        let source = cleanWikitext(cellContent)
                        if !source.isEmpty &&
                           !source.lowercased().contains("source") &&
                           !source.lowercased().contains("publication") {
                            currentSource = source
                        }
                    }
                }
            }
        }
        
        return scores.isEmpty ? nil : scores
    }
    
    /// Cleans wikitext markup from a string
    private func cleanWikitext(_ text: String) -> String {
        var cleaned = text
        
        // Remove templates {{template}} - must be done first, including nested ones
        // Use a loop to handle nested templates
        var previousCleaned = ""
        var iterations = 0
        while cleaned != previousCleaned && iterations < 10 {
            previousCleaned = cleaned
            // Remove {{...}} including nested content
            cleaned = cleaned.replacingOccurrences(of: "\\{\\{[^{}]*\\}\\}", with: "", options: .regularExpression)
            iterations += 1
        }
        
        // Remove incomplete template markers (e.g., "{{sfn", "{{rating", etc.)
        cleaned = cleaned.replacingOccurrences(of: "\\{\\{[^}]*$", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "^[^{]*\\}\\}", with: "", options: .regularExpression)
        
        // Remove HTML comments <!-- -->
        cleaned = cleaned.replacingOccurrences(of: "<!--[^>]*-->", with: "", options: .regularExpression)
        
        // Remove ref tags <ref>...</ref> and <ref ... />
        cleaned = cleaned.replacingOccurrences(of: "<ref[^>]*>.*?</ref>", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "<ref[^>/]*/>", with: "", options: .regularExpression)
        
        // Remove wikilinks [[Link|Display]] -> Display or [[Link]] -> Link
        cleaned = cleaned.replacingOccurrences(of: "\\[\\[([^|\\]]+)\\|([^\\]]+)\\]\\]", with: "$2", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[\\[([^\\]]+)\\]\\]", with: "$1", options: .regularExpression)
        
        // Remove external links [http://url Text] -> Text or [http://url] -> ""
        cleaned = cleaned.replacingOccurrences(of: "\\[https?://[^\\s\\]]+ ([^\\]]+)\\]", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[https?://[^\\s\\]]+\\]", with: "", options: .regularExpression)
        
        // Remove other HTML/XML tags
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Clean up bold/italic
        cleaned = cleaned.replacingOccurrences(of: "'''", with: "")
        cleaned = cleaned.replacingOccurrences(of: "''", with: "")
        
        // Remove table formatting attributes
        cleaned = cleaned.replacingOccurrences(of: "\\|\\s*style\\s*=\\s*[^|\\n]+", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\|\\s*class\\s*=\\s*[^|\\n]+", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\|\\s*align\\s*=\\s*[^|\\n]+", with: "", options: .regularExpression)
        
        // Convert star ratings to numeric scores
        cleaned = convertStarsToScore(cleaned)
        
        // Remove any remaining template artifacts or braces
        cleaned = cleaned.replacingOccurrences(of: "[{}]+", with: "", options: .regularExpression)
        
        // Trim whitespace and collapse multiple spaces
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return cleaned
    }
    
    /// Converts star ratings to numeric scores (e.g., ★★★★★ -> 10/10)
    private func convertStarsToScore(_ text: String) -> String {
        var result = text
        
        // Count filled stars (★) and half stars (½)
        let filledStars = result.components(separatedBy: "★").count - 1
        let halfStars = result.components(separatedBy: "½").count - 1
        
        // If we have stars, convert to score
        if filledStars > 0 || halfStars > 0 {
            let totalStars = Double(filledStars) + (Double(halfStars) * 0.5)
            
            // Convert 5-star scale to 10-point scale
            if totalStars <= 5.0 {
                let score = (totalStars / 5.0) * 10.0
                let scoreString = String(format: "%.1f/10", score).replacingOccurrences(of: ".0/10", with: "/10")
                
                // Replace all star characters with the score
                result = result.replacingOccurrences(of: "[★☆½]+", with: scoreString, options: .regularExpression)
            }
        }
        
        // Also handle text-based star ratings like "5/5 stars" or "4.5/5"
        if let range = result.range(of: "([0-9.]+)\\s*/\\s*5\\s*(?:stars?)?", options: .regularExpression) {
            let match = String(result[range])
            if let numRange = match.range(of: "[0-9.]+", options: .regularExpression),
               let starValue = Double(match[numRange]) {
                let score = (starValue / 5.0) * 10.0
                let scoreString = String(format: "%.1f/10", score).replacingOccurrences(of: ".0/10", with: "/10")
                result = result.replacingOccurrences(of: "([0-9.]+)\\s*/\\s*5\\s*(?:stars?)?", with: scoreString, options: .regularExpression)
            }
        }
        
        return result
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
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.cache[key] = result
            self?.saveCache()
        }
    }
    
    private func loadCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: "WikipediaCache"),
               let decoded = try? JSONDecoder().decode([String: WikipediaAlbumResult].self, from: data) {
                self?.cache = decoded
                print("Loaded \(decoded.count) Wikipedia entries from cache")
            }
        }
    }
    
    private func saveCache() {
        // Save to UserDefaults (called from within barrier already)
        let defaults = UserDefaults.standard
        if let encoded = try? JSONEncoder().encode(cache) {
            defaults.set(encoded, forKey: "WikipediaCache")
        }
    }
}

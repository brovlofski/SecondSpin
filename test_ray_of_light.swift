import Foundation

// We need to import the necessary types, but since this is a standalone script,
// let's create a minimal version of the parser and service to demonstrate

struct AlbumReviewScore {
    let source: String
    let rating: String
}

// Simpler version of the parser for demonstration
class WikipediaReviewParserDemo {
    
    static func parseReviewScores(from wikitext: String) -> [AlbumReviewScore] {
        print("=== Starting review score extraction ===")
        print("RAW_WIKI_TEXT length: \(wikitext.count) characters")
        
        // Find the review section
        guard let relevantSection = findReviewSection(in: wikitext) else {
            print("No review section found")
            return []
        }
        
        print("Found review section, length: \(relevantSection.count)")
        
        // Extract from ALL sources and combine results
        var allScores: [AlbumReviewScore] = []
        
        // Extract from {{Album ratings}} template
        if let templateScores = extractAlbumRatingsTemplate(from: relevantSection) {
            print("Extracted \(templateScores.count) scores from {{Album ratings}} template")
            allScores.append(contentsOf: templateScores)
        }
        
        // Extract from wikitable(s) - handle multiple tables
        let wikitableScores = extractAllWikitableScores(from: relevantSection)
        print("Extracted \(wikitableScores.count) scores from \(wikitableScores.count > 0 ? "wikitable(s)" : "wikitable")")
        allScores.append(contentsOf: wikitableScores)
        
        // Remove duplicates (same source and rating)
        let uniqueScores = removeDuplicates(from: allScores)
        print("Total unique scores extracted: \(uniqueScores.count)")
        
        return uniqueScores
    }
    
    private static func findReviewSection(in wikitext: String) -> String? {
        let sectionPatterns = [
            "==\\s*Professional\\s+ratings?\\s*==",
            "==\\s*Critical\\s+reception\\s*==",
            "==\\s*Reception\\s*==",
            "==\\s*Reviews\\s*==",
        ]
        
        for pattern in sectionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: wikitext, range: NSRange(wikitext.startIndex..., in: wikitext)) {
                let startIndex = wikitext.index(wikitext.startIndex, offsetBy: match.range.location)
                
                // Extract from this header to the next == header or end
                if let nextHeaderRange = wikitext.range(of: "\\n==", options: [.regularExpression], range: startIndex..<wikitext.endIndex) {
                    return String(wikitext[startIndex..<nextHeaderRange.lowerBound])
                } else {
                    return String(wikitext[startIndex...])
                }
            }
        }
        
        return nil
    }
    
    private static func extractAlbumRatingsTemplate(from text: String) -> [AlbumReviewScore]? {
        guard text.contains("{{Album ratings") || text.contains("{{album ratings") || 
              text.contains("{{Music ratings") || text.contains("{{music ratings") else {
            return nil
        }
        
        print("Found {{Album ratings}} or {{Music ratings}} template")
        
        var scores: [AlbumReviewScore] = []
        
        // Enhanced pattern to handle multiline and various formats
        let pattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n}]+)"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return scores.isEmpty ? nil : scores
        }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        print("Pattern found \(matches.count) rev/revScore pairs")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revNumber = Range(match.range(at: 1), in: text),
               let sourceRange = Range(match.range(at: 2), in: text),
               let ratingRange = Range(match.range(at: 3), in: text) {
                
                let revNum = String(text[revNumber])
                let rawSource = String(text[sourceRange])
                let rawRating = String(text[ratingRange])
                
                print("RAW pair (rev\(revNum)) - Source: '\(rawSource)' | Rating: '\(rawRating)'")
                
                // Clean source and rating with minimal processing
                let cleanedSource = cleanTextMinimal(rawSource)
                let cleanedRating = cleanTextMinimal(rawRating)
                
                print("CLEANED pair (rev\(revNum)) - Source: '\(cleanedSource)' | Rating: '\(cleanedRating)'")
                
                // Only add if both are non-empty after cleaning and not placeholder
                if !cleanedSource.isEmpty && !cleanedRating.isEmpty && !isPlaceholderRating(cleanedRating) {
                    // Check for duplicates
                    if !scores.contains(where: { $0.source == cleanedSource && $0.rating == cleanedRating }) {
                        scores.append(AlbumReviewScore(source: cleanedSource, rating: cleanedRating))
                        print("✓ Added: \(cleanedSource) — \(cleanedRating)")
                    } else {
                        print("✗ Skipped (duplicate)")
                    }
                } else {
                    print("✗ Rejected (empty after cleaning or placeholder)")
                }
            }
        }
        
        return scores.isEmpty ? nil : scores
    }
    
    /// Extracts scores from ALL wikitable sections in the text
    private static func extractAllWikitableScores(from text: String) -> [AlbumReviewScore] {
        var allScores: [AlbumReviewScore] = []
        
        // Find all table sections
        let tableSections = extractTableSections(from: text)
        print("Found \(tableSections.count) table sections")
        
        for (index, tableText) in tableSections.enumerated() {
            let scores = extractScoresFromTable(tableText)
            print("Table \(index + 1): extracted \(scores.count) scores")
            allScores.append(contentsOf: scores)
        }
        
        return allScores
    }
    
    /// Extracts individual table sections from text
    private static func extractTableSections(from text: String) -> [String] {
        var tables: [String] = []
        var inTable = false
        var currentTable = ""
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("{|") {
                inTable = true
                currentTable = line + "\n"
            } else if trimmed.hasPrefix("|}") && inTable {
                inTable = false
                currentTable += line + "\n"
                tables.append(currentTable)
                currentTable = ""
            } else if inTable {
                currentTable += line + "\n"
            }
        }
        
        // Handle case where table doesn't have proper closing
        if inTable && !currentTable.isEmpty {
            tables.append(currentTable)
        }
        
        return tables
    }
    
    /// Extracts scores from a single wikitable
    private static func extractScoresFromTable(_ tableText: String) -> [AlbumReviewScore] {
        var scores: [AlbumReviewScore] = []
        let lines = tableText.components(separatedBy: .newlines)
        var currentSource: String?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
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
                        let rawSource = cells[0]
                        let rawRating = cells[1]
                        
                        print("RAW table row - Source: '\(rawSource)' | Rating: '\(rawRating)'")
                        
                        let cleanedSource = cleanTextMinimal(rawSource)
                        let cleanedRating = cleanTextMinimal(rawRating)
                        
                        print("CLEANED table row - Source: '\(cleanedSource)' | Rating: '\(cleanedRating)'")
                        
                        if !cleanedSource.isEmpty && !cleanedRating.isEmpty &&
                           !isHeaderText(cleanedSource) && !isPlaceholderRating(cleanedRating) {
                            scores.append(AlbumReviewScore(source: cleanedSource, rating: cleanedRating))
                            print("✓ Added: \(cleanedSource) — \(cleanedRating)")
                        }
                    }
                } else {
                    // Single cell - alternate between source and rating
                    if let source = currentSource {
                        let cleanedRating = cleanTextMinimal(cellContent)
                        if !cleanedRating.isEmpty && !isPlaceholderRating(cleanedRating) {
                            scores.append(AlbumReviewScore(source: source, rating: cleanedRating))
                            print("✓ Added: \(source) — \(cleanedRating)")
                        }
                        currentSource = nil
                    } else {
                        let cleanedSource = cleanTextMinimal(cellContent)
                        if !cleanedSource.isEmpty && !isHeaderText(cleanedSource) {
                            currentSource = cleanedSource
                        }
                    }
                }
            }
        }
        
        return scores
    }
    
    // MARK: - Minimal Cleanup Functions
    
    /// Minimal text cleaning - just removes wiki markup, preserves original formatting
    static func cleanTextMinimal(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove citation templates (e.g., {{cite magazine}}, {{sfn}}, etc.)
        cleaned = removeCitationTemplatesMinimal(cleaned)
        
        // Remove wiki links but preserve the display text
        cleaned = cleanWikiLinksMinimal(cleaned)
        
        // Remove reference tags
        cleaned = cleaned.replacingOccurrences(
            of: "<ref[^>]*>.*?</ref>",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "<ref[^>/]*/?>",
            with: "",
            options: .regularExpression
        )
        
        // Remove reference markers like [1], [2], etc.
        cleaned = cleaned.replacingOccurrences(
            of: "\\[\\d+\\]",
            with: "",
            options: .regularExpression
        )
        
        // Remove HTML tags but keep content
        cleaned = cleaned.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        
        // Remove bold/italic markers
        cleaned = cleaned.replacingOccurrences(of: "'''", with: "")
        cleaned = cleaned.replacingOccurrences(of: "''", with: "")
        
        // Remove any remaining curly braces (but keep content inside)
        cleaned = cleaned.replacingOccurrences(of: "\\{\\{", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\\}\\}", with: "")
        
        // Normalize whitespace
        cleaned = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Minimal citation template removal - just removes the template, keeps preceding text
    private static func removeCitationTemplatesMinimal(_ text: String) -> String {
        var result = text
        
        // Remove complete citation templates
        let citationPatterns = [
            "\\{\\{cite[^}]*\\}\\}",
            "\\{\\{citation[^}]*\\}\\}",
            "\\{\\{sfn[^}]*\\}\\}",
            "\\{\\{harvnb[^}]*\\}\\}",
            "\\{\\{harv[^}]*\\}\\}",
            "\\{\\{cite book[^}]*\\}\\}",
            "\\{\\{cite web[^}]*\\}\\}",
            "\\{\\{cite news[^}]*\\}\\}",
            "\\{\\{cite journal[^}]*\\}\\}",
            "\\{\\{cite magazine[^}]*\\}\\}",
        ]
        
        for pattern in citationPatterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        return result
    }
    
    /// Minimal wiki link cleaning - preserves display text
    private static func cleanWikiLinksMinimal(_ text: String) -> String {
        var result = text
        
        // [[Link|Display Text]] -> Display Text
        result = result.replacingOccurrences(
            of: "\\[\\[([^|\\]]+)\\|([^\\]]+)\\]\\]",
            with: "$2",
            options: .regularExpression
        )
        
        // [[Link]] -> Link (remove brackets, keep text)
        result = result.replacingOccurrences(
            of: "\\[\\[([^\\]]+)\\]\\]",
            with: "$1",
            options: .regularExpression
        )
        
        // External links [http://... Display Text] -> Display Text
        result = result.replacingOccurrences(
            of: "\\[https?://[^\\s\\]]+ ([^\\]]+)\\]",
            with: "$1",
            options: .regularExpression
        )
        
        // Bare external links [http://...] -> remove
        result = result.replacingOccurrences(
            of: "\\[https?://[^\\s\\]]+\\]",
            with: "",
            options: .regularExpression
        )
        
        return result
    }
    
    // MARK: - Helper Functions
    
    /// Removes duplicate scores (same source and rating)
    private static func removeDuplicates(from scores: [AlbumReviewScore]) -> [AlbumReviewScore] {
        var seen = Set<String>()
        var unique: [AlbumReviewScore] = []
        
        for score in scores {
            let key = "\(score.source.lowercased()):\(score.rating)"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(score)
            }
        }
        
        return unique
    }
    
    private static func isHeaderText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("source") ||
               lower.contains("publication") ||
               lower.contains("rating") ||
               lower.contains("score") ||
               lower == "!" ||
               lower.isEmpty
    }
    
    /// Checks if text is a placeholder rating (e.g., "Rating", "Score", "N/A", etc.)
    private static func isPlaceholderRating(_ text: String) -> Bool {
        let lower = text.lowercased()
        let placeholders = [
            "rating", "score", "n/a", "na", "none", "tbd", "unknown", "not rated", 
            "unrated", "not available", "pending", "to be announced", "tba",
            "nil", "null", "—", "–", "-", "?", "??", "???"
        ]
        
        // Check for empty or very short meaningless strings
        if text.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        
        // Check against placeholders
        if placeholders.contains(lower) {
            return true
        }
        
        // Check for strings that are just punctuation or symbols
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 2 && trimmed.allSatisfy({ !$0.isLetter && !$0.isNumber }) {
            return true
        }
        
        return false
    }
}

// Let's fetch the actual Wikipedia data for "Ray of Light"
func fetchRayOfLightData() {
    print("=== Fetching Wikipedia data for Madonna - Ray of Light ===")
    
    // The Wikipedia API URL for fetching the wikitext
    let pageTitle = "Ray of Light (Madonna album)"
    let encodedTitle = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageTitle
    let urlString = "https://en.wikipedia.org/w/api.php?action=parse&page=\(encodedTitle)&prop=wikitext&format=json&origin=*"
    
    guard let url = URL(string: urlString) else {
        print("Failed to create URL")
        return
    }
    
    print("Fetching from: \(urlString)")
    
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            print("Error fetching data: \(error)")
            return
        }
        
        guard let data = data else {
            print("No data received")
            return
        }
        
        do {
            // Parse the JSON response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let parse = json["parse"] as? [String: Any],
               let wikitextDict = parse["wikitext"] as? [String: Any],
               let wikitext = wikitextDict["*"] as? String {
                
                print("\n=== Successfully fetched wikitext ===")
                print("Total wikitext length: \(wikitext.count) characters")
                
                // Now parse the review scores
                let scores = WikipediaReviewParserDemo.parseReviewScores(from: wikitext)
                
                print("\n=== FINAL EXTRACTED REVIEW SCORES ===")
                print("Total scores found: \(scores.count)")
                print("\nDetailed list:")
                for (index, score) in scores.enumerated() {
                    print("\(index + 1). \(score.source): \(score.rating)")
                }
                
                // Also show a sample of the raw wikitext around the review section
                if let reviewSection = findReviewSection(in: wikitext) {
                    print("\n=== SAMPLE OF REVIEW SECTION WIKITEXT ===")
                    let lines = reviewSection.components(separatedBy: .newlines)
                    print("First 50 lines of review section:")
                    for (i, line) in lines.prefix(50).enumerated() {
                        print("\(i + 1): \(line)")
                    }
                }
                
            } else {
                print("Failed to parse JSON response")
            }
        } catch {
            print("JSON parsing error: \(error)")
        }
    }
    
    task.resume()
    
    // Keep the program running long enough to get the response
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 10))
}

// Helper function to find review section (copied from parser)
func findReviewSection(in wikitext: String) -> String? {
    let sectionPatterns = [
        "==\\s*Professional\\s+ratings?\\s*==",
        "==\\s*Critical\\s+reception\\s*==",
        "==\\s*Reception\\s*==",
        "==\\s*Reviews\\s*==",
    ]
    
    for pattern in sectionPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: wikitext, range: NSRange(wikitext.startIndex..., in: wikitext)) {
            let startIndex = wikitext.index(wikitext.startIndex, offsetBy: match.range.location)
            
            // Extract from this header to the next == header or end
            if let nextHeaderRange = wikitext.range(of: "\\n==", options: [.regularExpression], range: startIndex..<wikitext.endIndex) {
                return String(wikitext[startIndex..<nextHeaderRange.lowerBound])
            } else {
                return String(wikitext[startIndex...])
            }
        }
    }
    
    return nil
}

// Run the fetch
fetchRayOfLightData()
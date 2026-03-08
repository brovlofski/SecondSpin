//
//  WikipediaReviewParser.swift
//  VinylVault
//
//  Dedicated parser for extracting Wikipedia review scores as raw text.
//

import Foundation

struct WikipediaReviewParser {
    
    // MARK: - Debug Logging
    
    private static var debugEnabled = true
    
    static func enableDebug(_ enabled: Bool) {
        debugEnabled = enabled
    }
    
    private static func log(_ message: String) {
        if debugEnabled {
            print("[WikipediaReviewParser] \(message)")
        }
    }
    
    // MARK: - Main Parsing Entry Point
    
    /// Extracts review scores from Wikipedia wikitext, sorted with priority publications first
    static func parseReviewScores(from wikitext: String) -> [AlbumReviewScore] {
        log("=== Starting review score extraction ===")
        log("RAW_WIKI_TEXT length: \(wikitext.count) characters")
        
        // Find the review section
        guard let relevantSection = findReviewSection(in: wikitext) else {
            log("No review section found")
            return []
        }
        
        log("Found review section, length: \(relevantSection.count)")
        
        // Extract from ALL sources and combine results
        var allScores: [AlbumReviewScore] = []
        
        // Extract from {{Album ratings}} template
        if let templateScores = extractAlbumRatingsTemplate(from: relevantSection) {
            log("Extracted \(templateScores.count) scores from {{Album ratings}} template")
            allScores.append(contentsOf: templateScores)
        }
        
        // Extract from wikitable(s) - handle multiple tables
        let wikitableScores = extractAllWikitableScores(from: relevantSection)
        log("Extracted \(wikitableScores.count) scores from \(wikitableScores.count > 0 ? "wikitable(s)" : "wikitable")")
        allScores.append(contentsOf: wikitableScores)
        
        // Remove duplicates (same source and rating)
        let uniqueScores = removeDuplicates(from: allScores)
        log("Total unique scores extracted: \(uniqueScores.count)")
        
        return sortReviewScores(uniqueScores)
    }

    // MARK: - Sorting

    /// Sorts review scores: Allmusic, Pitchfork, Rolling Stone first (in that order),
    /// remaining publications sorted alphabetically.
    static func sortReviewScores(_ scores: [AlbumReviewScore]) -> [AlbumReviewScore] {
        let priorityOrder = ["allmusic", "pitchfork", "rolling stone"]

        return scores.sorted { a, b in
            let aLower = a.source.lowercased()
            let bLower = b.source.lowercased()

            let aIdx = priorityOrder.firstIndex(where: { aLower.contains($0) })
            let bIdx = priorityOrder.firstIndex(where: { bLower.contains($0) })

            switch (aIdx, bIdx) {
            case let (ai?, bi?): return ai < bi
            case (.some, nil):   return true
            case (nil, .some):   return false
            case (nil, nil):     return a.source.localizedCaseInsensitiveCompare(b.source) == .orderedAscending
            }
        }
    }

    // MARK: - Section Finding
    
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
    
    // MARK: - Template Extraction
    
    private static func extractAlbumRatingsTemplate(from text: String) -> [AlbumReviewScore]? {
        guard text.contains("{{Album ratings") || text.contains("{{album ratings") || 
              text.contains("{{Music ratings") || text.contains("{{music ratings") else {
            return nil
        }
        
        log("Found {{Album ratings}} or {{Music ratings}} template")
        
        var scores: [AlbumReviewScore] = []
        
        // Improved pattern to capture full rating templates like {{Rating|X|Y}}
        // Captures: | revN = Source | revNscore = Rating (handles templates with pipes, refs, etc.)
        // Pattern explanation: (?:[^{}|\\n]|\\{\\{[^{}]*\\}\\})*? matches either:
        //   - Non-brace, non-pipe, non-newline characters
        //   - OR complete {{...}} templates (which can contain pipes)
        let pattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*((?:[^{}|\\n]|\\{\\{[^{}]*\\}\\})*?)(?=(?:<ref|\\||$))"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return scores.isEmpty ? nil : scores
        }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        log("Pattern found \(matches.count) rev/revScore pairs")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revNumber = Range(match.range(at: 1), in: text),
               let sourceRange = Range(match.range(at: 2), in: text),
               let ratingRange = Range(match.range(at: 3), in: text) {
                
                let revNum = String(text[revNumber])
                let rawSource = String(text[sourceRange])
                let rawRating = String(text[ratingRange])
                
                log("RAW pair (rev\(revNum)) - Source: '\(rawSource)' | Rating: '\(rawRating)'")
                
                // Clean source and rating with improved processing
                let cleanedSource = cleanTextImproved(rawSource)
                let cleanedRating = cleanRatingText(rawRating)  // Special cleaning for ratings
                
                log("CLEANED pair (rev\(revNum)) - Source: '\(cleanedSource)' | Rating: '\(cleanedRating)'")
                
                // Only add if both are non-empty after cleaning and not placeholder
                if !cleanedSource.isEmpty && !cleanedRating.isEmpty && !isPlaceholderRating(cleanedRating) {
                    // Check for duplicates
                    if !scores.contains(where: { $0.source == cleanedSource && $0.rating == cleanedRating }) {
                        scores.append(AlbumReviewScore(source: cleanedSource, rating: cleanedRating))
                        log("✓ Added: \(cleanedSource) — \(cleanedRating)")
                    } else {
                        log("✗ Skipped (duplicate)")
                    }
                } else {
                    log("✗ Rejected (empty after cleaning or placeholder)")
                }
            }
        }
        
        return scores.isEmpty ? nil : scores
    }
    
    // MARK: - Wikitable Extraction
    
    /// Extracts scores from ALL wikitable sections in the text
    private static func extractAllWikitableScores(from text: String) -> [AlbumReviewScore] {
        var allScores: [AlbumReviewScore] = []
        
        // Find all table sections
        let tableSections = extractTableSections(from: text)
        log("Found \(tableSections.count) table sections")
        
        for (index, tableText) in tableSections.enumerated() {
            let scores = extractScoresFromTable(tableText)
            log("Table \(index + 1): extracted \(scores.count) scores")
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
        
        // Handle case where table doesn't have proper closing (shouldn't happen in Wikipedia)
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
                        
                        log("RAW table row - Source: '\(rawSource)' | Rating: '\(rawRating)'")
                        
                        let cleanedSource = cleanTextMinimal(rawSource)
                        let cleanedRating = cleanTextMinimal(rawRating)
                        
                        log("CLEANED table row - Source: '\(cleanedSource)' | Rating: '\(cleanedRating)'")
                        
                        if !cleanedSource.isEmpty && !cleanedRating.isEmpty &&
                           !isHeaderText(cleanedSource) && !isPlaceholderRating(cleanedRating) {
                            scores.append(AlbumReviewScore(source: cleanedSource, rating: cleanedRating))
                            log("✓ Added: \(cleanedSource) — \(cleanedRating)")
                        }
                    }
                } else {
                    // Single cell - alternate between source and rating
                    if let source = currentSource {
                        let cleanedRating = cleanTextMinimal(cellContent)
                        if !cleanedRating.isEmpty && !isPlaceholderRating(cleanedRating) {
                            scores.append(AlbumReviewScore(source: source, rating: cleanedRating))
                            log("✓ Added: \(source) — \(cleanedRating)")
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
    
    // MARK: - Text Cleaning Functions
    
    /// Improved text cleaning for source names
    private static func cleanTextImproved(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove wiki links but preserve the display text
        cleaned = cleanWikiLinksMinimal(cleaned)
        
        // Remove quotes
        cleaned = cleaned.replacingOccurrences(of: "'''", with: "")
        cleaned = cleaned.replacingOccurrences(of: "''", with: "")
        
        // Remove any remaining brackets
        cleaned = cleaned.replacingOccurrences(of: "\\[\\[", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\\]\\]", with: "")
        
        // Normalize whitespace
        cleaned = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Special cleaning for rating text - extracts readable ratings from templates
    private static func cleanRatingText(_ text: String) -> String {
        var rating = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First, handle {{Rating|X|Y}} templates
        let ratingPattern = "\\{\\{[Rr]ating\\|([0-9.]+)\\|([0-9.]+)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: ratingPattern) {
            if let match = regex.firstMatch(in: rating, range: NSRange(rating.startIndex..., in: rating)),
               match.numberOfRanges >= 3,
               let numeratorRange = Range(match.range(at: 1), in: rating),
               let denominatorRange = Range(match.range(at: 2), in: rating) {
                
                let numerator = String(rating[numeratorRange])
                let denominator = String(rating[denominatorRange])
                return "\(numerator)/\(denominator)"
            }
        }
        
        // Handle {{rating-Christgau|X}} templates
        let christgauPattern = "\\{\\{[Rr]ating-Christgau\\|([^}]+)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: christgauPattern) {
            if let match = regex.firstMatch(in: rating, range: NSRange(rating.startIndex..., in: rating)),
               match.numberOfRanges >= 2,
               let gradeRange = Range(match.range(at: 1), in: rating) {
                
                return String(rating[gradeRange])
            }
        }
        
        // Handle {{rating|X|Y}} (lowercase)
        let ratingLowerPattern = "\\{\\{rating\\|([0-9.]+)\\|([0-9.]+)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: ratingLowerPattern) {
            if let match = regex.firstMatch(in: rating, range: NSRange(rating.startIndex..., in: rating)),
               match.numberOfRanges >= 3,
               let numeratorRange = Range(match.range(at: 1), in: rating),
               let denominatorRange = Range(match.range(at: 2), in: rating) {
                
                let numerator = String(rating[numeratorRange])
                let denominator = String(rating[denominatorRange])
                return "\(numerator)/\(denominator)"
            }
        }
        
        // Remove ref tags
        rating = rating.replacingOccurrences(
            of: "<ref[^>]*>.*?</ref>",
            with: "",
            options: .regularExpression
        )
        
        rating = rating.replacingOccurrences(
            of: "<ref[^>/]*/>",
            with: "",
            options: .regularExpression
        )
        
        // Remove citation templates
        rating = rating.replacingOccurrences(
            of: "\\{\\{[^}]*cite[^}]*\\}\\}",
            with: "",
            options: .regularExpression
        )
        
        // Remove any remaining {{...}} templates
        rating = rating.replacingOccurrences(
            of: "\\{\\{[^}]*\\}\\}",
            with: "",
            options: .regularExpression
        )
        
        // Remove any remaining <...> tags
        rating = rating.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        
        // Remove reference markers
        rating = rating.replacingOccurrences(
            of: "\\[\\d+\\]",
            with: "",
            options: .regularExpression
        )
        
        // Normalize whitespace
        rating = rating.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        return rating.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
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

// MARK: - String Extension for Pattern Matching

private extension String {
    func matches(pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}
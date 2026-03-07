//
//  WikipediaReviewParser.swift
//  VinylVault
//
//  Dedicated parser for extracting and cleaning Wikipedia review scores.
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
    
    /// Extracts review scores from Wikipedia wikitext
    static func parseReviewScores(from wikitext: String) -> [AlbumReviewScore] {
        log("=== Starting review score extraction ===")
        log("RAW_WIKI_TEXT length: \(wikitext.count) characters")
        
        // Find the review section
        guard let relevantSection = findReviewSection(in: wikitext) else {
            log("No review section found")
            return []
        }
        
        log("Found review section, length: \(relevantSection.count)")
        
        // Try different extraction methods
        if let scores = extractAlbumRatingsTemplate(from: relevantSection) {
            log("Extracted \(scores.count) scores from {{Album ratings}} template")
            return scores
        }
        
        if let scores = extractWikitableScores(from: relevantSection) {
            log("Extracted \(scores.count) scores from wikitable")
            return scores
        }
        
        log("No scores extracted")
        return []
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
        guard text.contains("{{Album ratings") || text.contains("{{album ratings") else {
            return nil
        }
        
        log("Found {{Album ratings}} template")
        
        var scores: [AlbumReviewScore] = []
        
        // Enhanced pattern to handle multiline and various formats
        // Pattern 1: Standard |revN = Source |revNscore = Rating (case-insensitive)
        let pattern1 = "\\|\\s*rev(\\d+)\\s*=\\s*([^|\\n]+?)\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n}]+)"
        
        // Pattern 2: Handle cases where source/rating span multiple lines
        let pattern2 = "\\|\\s*rev(\\d+)\\s*=\\s*([^|]+?)\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|]+?)(?=\\||\\}\\})"
        
        for pattern in [pattern1, pattern2] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                continue
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
                    
                    // Clean source and rating separately
                    let cleanedSource = cleanPublicationName(rawSource)
                    let cleanedRating = cleanRatingValue(rawRating)
                    
                    log("CLEANED pair (rev\(revNum)) - Source: '\(cleanedSource)' | Rating: '\(cleanedRating)'")
                    
                    // Only add if both are non-empty after cleaning and not already added
                    if !cleanedSource.isEmpty && !cleanedRating.isEmpty {
                        // Check for duplicates
                        if !scores.contains(where: { $0.source == cleanedSource && $0.rating == cleanedRating }) {
                            scores.append(AlbumReviewScore(source: cleanedSource, rating: cleanedRating))
                            log("✓ Added: \(cleanedSource) — \(cleanedRating)")
                        } else {
                            log("✗ Skipped (duplicate)")
                        }
                    } else {
                        log("✗ Rejected (empty after cleaning)")
                    }
                }
            }
            
            // If we found scores with the first pattern, don't try the second
            if !scores.isEmpty {
                break
            }
        }
        
        return scores.isEmpty ? nil : scores
    }
    
    // MARK: - Wikitable Extraction
    
    private static func extractWikitableScores(from text: String) -> [AlbumReviewScore]? {
        guard text.contains("{|") && text.contains("|}") else {
            return nil
        }
        
        log("Found wikitable")
        
        var scores: [AlbumReviewScore] = []
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
                        let rawSource = cells[0]
                        let rawRating = cells[1]
                        
                        log("RAW table row - Source: '\(rawSource)' | Rating: '\(rawRating)'")
                        
                        let cleanedSource = cleanPublicationName(rawSource)
                        let cleanedRating = cleanRatingValue(rawRating)
                        
                        log("CLEANED table row - Source: '\(cleanedSource)' | Rating: '\(cleanedRating)'")
                        
                        if !cleanedSource.isEmpty && !cleanedRating.isEmpty &&
                           !isHeaderText(cleanedSource) {
                            scores.append(AlbumReviewScore(source: cleanedSource, rating: cleanedRating))
                            log("✓ Added: \(cleanedSource) — \(cleanedRating)")
                        }
                    }
                } else {
                    // Single cell - alternate between source and rating
                    if let source = currentSource {
                        let cleanedRating = cleanRatingValue(cellContent)
                        if !cleanedRating.isEmpty {
                            scores.append(AlbumReviewScore(source: source, rating: cleanedRating))
                            log("✓ Added: \(source) — \(cleanedRating)")
                        }
                        currentSource = nil
                    } else {
                        let cleanedSource = cleanPublicationName(cellContent)
                        if !cleanedSource.isEmpty && !isHeaderText(cleanedSource) {
                            currentSource = cleanedSource
                        }
                    }
                }
            }
        }
        
        return scores.isEmpty ? nil : scores
    }
    
    // MARK: - Cleanup Functions
    
    /// Cleans publication names, preserving the readable text
    static func cleanPublicationName(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove citations and references
        cleaned = removeReferences(cleaned)
        
        // Clean wiki links but preserve the display text
        cleaned = cleanWikiLinks(cleaned)
        
        // Remove bold/italic markers
        cleaned = cleaned.replacingOccurrences(of: "'''", with: "")
        cleaned = cleaned.replacingOccurrences(of: "''", with: "")
        
        // Remove remaining HTML
        cleaned = removeHTMLTags(cleaned)
        
        // Normalize whitespace
        cleaned = normalizeWhitespace(cleaned)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Cleans rating values, preserving original format (stars, fractions, percentages, etc.)
    static func cleanRatingValue(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        log("  Cleaning rating value: '\(cleaned)'")
        
        // FIRST: Extract rating from {{rating|X|Y}} template BEFORE any other processing
        if let extractedRating = extractRatingTemplate(cleaned) {
            log("  Extracted from {{rating}} template: '\(extractedRating)'")
            return extractedRating
        }
        
        // SECOND: Check for {{Album ratings}} star rating pattern like {{rating|3.5|5}}
        // This handles nested rating templates within the Album ratings template
        if cleaned.contains("{{") && cleaned.contains("rating") {
            if let extractedRating = extractRatingTemplate(cleaned) {
                log("  Extracted nested rating: '\(extractedRating)'")
                return extractedRating
            }
        }
        
        // Remove citations and references FIRST (before other processing)
        cleaned = removeReferences(cleaned)
        
        // Remove wiki links (but keep the text for display)
        cleaned = cleanWikiLinks(cleaned)
        
        // Remove bold/italic
        cleaned = cleaned.replacingOccurrences(of: "'''", with: "")
        cleaned = cleaned.replacingOccurrences(of: "''", with: "")
        
        // IMPORTANT: Check if this is a star rating BEFORE removing HTML
        // Star ratings often use Unicode characters or special symbols
        if containsStarRating(cleaned) {
            // Keep star symbols - just remove HTML tags and normalize
            cleaned = removeHTMLTags(cleaned)
            cleaned = normalizeWhitespace(cleaned)
            log("  Preserved star rating: '\(cleaned)'")
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // For non-star ratings, continue with normal cleaning
        cleaned = removeHTMLTags(cleaned)
        
        // Only remove template markers if they're not part of a rating value
        if !cleaned.contains("/") && !cleaned.matches(pattern: "[0-9]") {
            cleaned = cleaned.replacingOccurrences(of: "{{", with: "")
            cleaned = cleaned.replacingOccurrences(of: "}}", with: "")
        }
        
        // Normalize whitespace
        cleaned = normalizeWhitespace(cleaned)
        
        log("  Final cleaned rating: '\(cleaned)'")
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Checks if text contains star rating symbols
    private static func containsStarRating(_ text: String) -> Bool {
        // Check for various star symbols and rating indicators
        let starPatterns = [
            "★", "☆", "⭐", "✭", "✯",  // Star symbols
            "♪", "♫", "♬",              // Music note symbols sometimes used
            "◼︎", "■",                  // Black squares sometimes used
        ]
        return starPatterns.contains { text.contains($0) }
    }
    
    /// Extracts numeric rating from {{rating|X|Y}} or {{Rating|X|Y}} template
    private static func extractRatingTemplate(_ text: String) -> String? {
        let pattern = "\\{\\{[Rr]ating\\|(\\d+(?:\\.\\d+)?)\\|(\\d+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: text),
              let maxRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        
        let value = String(text[valueRange])
        let max = String(text[maxRange])
        
        return "\(value)/\(max)"
    }
    
    // MARK: - Markup Removal Helpers
    
    private static func removeReferences(_ text: String) -> String {
        var result = text
        
        // Remove <ref>...</ref> tags
        result = result.replacingOccurrences(
            of: "<ref[^>]*>.*?</ref>",
            with: "",
            options: .regularExpression
        )
        
        // Remove <ref ... /> self-closing tags
        result = result.replacingOccurrences(
            of: "<ref[^>/]*/?>",
            with: "",
            options: .regularExpression
        )
        
        // Remove [1], [2], etc. reference markers
        result = result.replacingOccurrences(
            of: "\\[\\d+\\]",
            with: "",
            options: .regularExpression
        )
        
        // Remove {{sfn|...}} and {{cite|...}} citations
        result = result.replacingOccurrences(
            of: "\\{\\{sfn\\|[^}]*\\}\\}",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "\\{\\{cite[^}]*\\}\\}",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        
        // Remove HTML comments
        result = result.replacingOccurrences(
            of: "<!--.*?-->",
            with: "",
            options: .regularExpression
        )
        
        return result
    }
    
    private static func cleanWikiLinks(_ text: String) -> String {
        var result = text
        
        // [[Link|Display Text]] -> Display Text
        result = result.replacingOccurrences(
            of: "\\[\\[([^|\\]]+)\\|([^\\]]+)\\]\\]",
            with: "$2",
            options: .regularExpression
        )
        
        // [[Link]] -> Link
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
        
        // Bare external links [http://...]
        result = result.replacingOccurrences(
            of: "\\[https?://[^\\s\\]]+\\]",
            with: "",
            options: .regularExpression
        )
        
        return result
    }
    
    private static func removeHTMLTags(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
    }
    
    private static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
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

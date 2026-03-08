import Foundation

// Test the improved WikipediaReviewParser logic with Ray of Light data

struct AlbumReviewScore {
    let source: String
    let rating: String
}

// Copy of the improved parser logic
class ImprovedWikipediaParser {
    
    static func parseReviewScores(from wikitext: String) -> [AlbumReviewScore] {
        print("=== Testing Improved Parser ===")
        
        // Find the review section
        guard let relevantSection = findReviewSection(in: wikitext) else {
            print("No review section found")
            return []
        }
        
        print("Found review section, length: \(relevantSection.count) characters")
        
        // Extract from {{Album ratings}} template
        if let templateScores = extractAlbumRatingsTemplate(from: relevantSection) {
            print("\nExtracted \(templateScores.count) scores from {{Album ratings}} template")
            return templateScores
        }
        
        return []
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
        
        // Improved pattern to capture full rating templates like {{Rating|X|Y}}
        // Captures: | revN = Source | revNscore = Rating (handles templates, refs, etc.)
        let pattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n]+?)(?=(?:<ref|\\||\\}\\}|$))"
        
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
                
                print("\n--- Entry rev\(revNum) ---")
                print("RAW SOURCE: '\(rawSource)'")
                print("RAW RATING: '\(rawRating)'")
                
                // Clean source and rating with improved processing
                let cleanedSource = cleanTextImproved(rawSource)
                let cleanedRating = cleanRatingText(rawRating)  // Special cleaning for ratings
                
                print("CLEANED: '\(cleanedSource)' → '\(cleanedRating)'")
                
                // Only add if both are non-empty after cleaning and not placeholder
                if !cleanedSource.isEmpty && !cleanedRating.isEmpty && !isPlaceholderRating(cleanedRating) {
                    scores.append(AlbumReviewScore(source: cleanedSource, rating: cleanedRating))
                }
            }
        }
        
        return scores.isEmpty ? nil : scores
    }
    
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
        
        return result
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

// Fetch Ray of Light data and test the parser
func testImprovedParserWithRayOfLight() {
    print("=== FETCHING RAY OF LIGHT WIKIPEDIA PAGE ===")
    
    let pageTitle = "Ray of Light"
    let encodedTitle = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageTitle
    let urlString = "https://en.wikipedia.org/w/api.php?action=parse&page=\(encodedTitle)&prop=wikitext&format=json&origin=*"
    
    guard let url = URL(string: urlString) else {
        print("Failed to create URL")
        return
    }
    
    let semaphore = DispatchSemaphore(value: 0)
    
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        defer { semaphore.signal() }
        
        guard let data = data else {
            print("No data received")
            return
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let parse = json["parse"] as? [String: Any],
               let wikitextDict = parse["wikitext"] as? [String: Any],
               let wikitext = wikitextDict["*"] as? String {
                
                print("Successfully fetched wikitext (\(wikitext.count) characters)")
                
                // Test the improved parser
                let scores = ImprovedWikipediaParser.parseReviewScores(from: wikitext)
                
                print("\n=== FINAL RESULTS FROM IMPROVED PARSER ===")
                print("Total scores extracted: \(scores.count)")
                
                for (i, score) in scores.enumerated() {
                    print("\(i+1). \(score.source): \(score.rating)")
                }
                
                // Show what the old parser would have extracted
                print("\n=== FOR COMPARISON: OLD PARSER OUTPUT ===")
                print("1. 'Chicago Tribune': {{Rating")
                print("2. 'Entertainment Weekly': A−")
                print("3. 'The Guardian': {{Rating")
                print("4. 'NME': 8/10{{cite magazine")
                print("5. 'Rolling Stone': {{Rating")
                print("6. 'The Sydney Morning Herald': {{Rating")
                print("7. 'USA Today': {{Rating")
                print("8. AllMusic: {{Rating")
                print("9. 'Encyclopedia of Popular Music': {{Rating")
                print("10. 'MusicHound Rock': {{rating")
                print("11. 'The Rolling Stone Album Guide': {{Rating")
                print("12. 'Slant Magazine': {{Rating")
                
            } else {
                print("Failed to parse JSON")
            }
        } catch {
            print("Error: \(error)")
        }
    }
    
    task.resume()
    _ = semaphore.wait(timeout: .now() + 30)
}

// Run the test
testImprovedParserWithRayOfLight()
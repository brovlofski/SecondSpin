import Foundation

// Final verification test for WikipediaReviewParser improvements
// This tests the actual parser logic with the improved regex

// Mock AlbumReviewScore struct for testing
struct AlbumReviewScore: Identifiable, Equatable {
    let id = UUID()
    let source: String
    let rating: String
    
    static func == (lhs: AlbumReviewScore, rhs: AlbumReviewScore) -> Bool {
        return lhs.source == rhs.source && lhs.rating == rhs.rating
    }
}

// Copy of the improved WikipediaReviewParser with our final regex fix
class WikipediaReviewParser {
    
    static func parseReviewScores(from wikitext: String) -> [AlbumReviewScore] {
        print("=== Testing IMPROVED PARSER ===")
        
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
        
        // IMPROVED PATTERN - FINAL VERSION
        // Pattern explanation: (?:[^{}|\\n]|\\{\\{[^{}]*\\}\\})*? matches either:
        //   - Non-brace, non-pipe, non-newline characters
        //   - OR complete {{...}} templates (which can contain pipes)
        let pattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*((?:[^{}|\\n]|\\{\\{[^{}]*\\}\\})*?)(?=(?:<ref|\\||$))"
        
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

// Test the improvement with a sample from Ray of Light
func testFinalVerification() {
    print("\n\n=== FINAL VERIFICATION TEST ===\n")
    
    // Sample text from Ray of Light containing {{Rating|X|Y}} templates
    let sampleWikitext = """
== Critical reception ==
{{Album ratings
| rev1 = ''[[Chicago Tribune]]''
| rev1Score = {{Rating|3.5|4}}<ref>{{cite news|last=Kot|first=Greg|author-link=Greg Kot|date=March 1, 1998|url=https://www.chicagotribune.com/1998/03/01/new-material-girl/|title=New-Material Girl|newspaper=[[Chicago Tribune]]|access-date=September 22, 2015|archive-date=March 4, 2016|archive-url=https://web.archive.org/web/20160304110827/http://articles.chicagotribune.com/1998-03-01/news/9803010300_1_shep-pettibone-pop-stars-william-orbit|url-status=live}}</ref>
| rev2 = ''[[Entertainment Weekly]]''
| rev2Score = A−<ref name="ew" />
| rev3 = ''[[The Guardian]]''
| rev3Score = {{Rating|4|5}}<ref name="The Guardian Review">{{cite news|last=Sullivan|first=Caroline|title=Madonna: ''Ray of Light'' (WEA)|newspaper=[[The Guardian]]|date=February 27, 1998|page=18|issn=0261-3077}}</ref>
| rev4 = ''[[NME]]''
| rev4Score = 8/10<ref>{{cite magazine |url=https://www.nme.com/reviews/reviews/19980101000248reviews.html|title=Madonna – ''Ray of Light'' |last=Moody |first=Paul |magazine=[[NME]] |page=43|date=February 28, 1998|access-date=March 27, 2020|archive-url=https://web.archive.org/web/20000817192218/http://www.nme.com/reviews/reviews/19980101000248reviews.html|archive-date=August 17, 2000|url-status=dead}}</ref>
| rev5 = ''[[Rolling Stone]]''
| rev5score = {{Rating|4|5}}<ref name="Rolling Stone Review">{{cite magazine|last=Wild|first=David|title=Madonna: ''Ray of Light''|url=https://www.rollingstone.com/music/music-album-reviews/ray-of-light-252039/|magazine=[[Rolling Stone]]|date=March 19, 1998|access-date=July 19, 2015|archive-url=https://web.archive.org/web/20170223014433/http://www.rollingstone.com/music/albumreviews/ray-of-light-19980319|archive-date=February 23, 2017|url-status=live}}</ref>
}}
Some other content here.
"""
    
    print("Testing with sample wikitext containing {{Rating|X|Y}} templates...")
    
    let scores = WikipediaReviewParser.parseReviewScores(from: sampleWikitext)
    
    print("\n=== FINAL RESULTS ===")
    print("Total scores extracted: \(scores.count)")
    
    for (i, score) in scores.enumerated() {
        print("\(i+1). \(score.source): \(score.rating)")
    }
    
    // Verify expected results
    let expectedResults = [
        ("Chicago Tribune", "3.5/4"),
        ("Entertainment Weekly", "A−"),
        ("The Guardian", "4/5"),
        ("NME", "8/10"),
        ("Rolling Stone", "4/5")
    ]
    
    print("\n=== VERIFICATION ===")
    
    var allPassed = true
    for (expectedSource, expectedRating) in expectedResults {
        if let match = scores.first(where: { $0.source == expectedSource }) {
            if match.rating == expectedRating {
                print("✓ \(expectedSource): \(expectedRating) - CORRECT")
            } else {
                print("✗ \(expectedSource): Expected '\(expectedRating)', got '\(match.rating)' - INCORRECT")
                allPassed = false
            }
        } else {
            print("✗ \(expectedSource): NOT FOUND - MISSING")
            allPassed = false
        }
    }
    
    if allPassed {
        print("\n✅ ALL TESTS PASSED! The parser is correctly extracting {{Rating|X|Y}} templates.")
    } else {
        print("\n❌ SOME TESTS FAILED. The parser still has issues.")
    }
    
    // Show what the OLD parser would have produced
    print("\n=== OLD PARSER OUTPUT (FOR COMPARISON) ===")
    print("The old parser would have produced:")
    print("1. 'Chicago Tribune': {{Rating")
    print("2. 'Entertainment Weekly': A−")
    print("3. 'The Guardian': {{Rating")
    print("4. 'NME': 8/10")
    print("5. 'Rolling Stone': {{Rating")
    
    print("\n=== IMPROVEMENT SUMMARY ===")
    print("• Old parser: Would capture '{{Rating' (truncated at pipe)")
    print("• New parser: Captures full '{{Rating|3.5|4}}' template")
    print("• Rating cleaning: Extracts '3.5/4' from template")
    print("• Result: Complete, readable ratings instead of truncated template names")
}

// Run the test
testFinalVerification()

print("\n\n=== SUMMARY OF CHANGES MADE ===")
print("1. Fixed regex pattern to handle {{Rating|X|Y}} templates with pipes")
print("   OLD: \\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n]+?)(?=(?:<ref|\\||\\}\\}|$))")
print("   NEW: \\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*((?:[^{}|\\n]|\\{\\{[^{}]*\\}\\})*?)(?=(?:<ref|\\||$))")
print("2. Added cleanRatingText() function to extract X/Y from {{Rating|X|Y}} templates")
print("3. Improved text cleaning to preserve meaningful rating formats")
print("4. Tested with real Ray of Light Wikipedia data to verify improvements")
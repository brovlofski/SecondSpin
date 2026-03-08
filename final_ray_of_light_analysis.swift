import Foundation

// Final comprehensive analysis of Ray of Light review data
func analyzeRayOfLightReviews() {
    print("=== COMPREHENSIVE RAY OF LIGHT REVIEW ANALYSIS ===")
    
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
                
                print("Total wikitext length: \(wikitext.count) characters")
                
                // Find the review section
                if let reviewRange = wikitext.range(of: "== Critical reception ==") {
                    let startIndex = reviewRange.lowerBound
                    let afterReview = wikitext[startIndex...]
                    
                    // Find the next == section
                    if let nextSectionRange = afterReview.range(of: "\\n==", options: .regularExpression, range: afterReview.index(after: startIndex)..<afterReview.endIndex) {
                        let reviewSection = String(afterReview[..<nextSectionRange.lowerBound])
                        
                        print("\n=== RAW DATA FROM REVIEW SECTION ===")
                        print("Section length: \(reviewSection.count) characters")
                        
                        // Extract ALL review entries from the {{Music ratings}} template
                        print("\n=== EXTRACTING FROM {{Music ratings}} TEMPLATE ===")
                        
                        // Better regex that captures everything until the next pipe or closing braces
                        // Pattern: | revX = source | revXscore = rating (with possible refs/templates)
                        let revPattern = "\\|\\s*rev(\\d+)\\s*=\\s*([^|\\n]+?)\\s*\\|\\s*rev\\d+[Ss]core\\s*=\\s*([^|\\n]+?)(?=\\s*\\||\\s*\\}\\})"
                        
                        if let regex = try? NSRegularExpression(pattern: revPattern, options: .dotMatchesLineSeparators) {
                            let matches = regex.matches(in: reviewSection, range: NSRange(reviewSection.startIndex..., in: reviewSection))
                            print("Found \(matches.count) rev/score pairs")
                            
                            var rawEntries: [(source: String, rating: String)] = []
                            
                            for match in matches {
                                if match.numberOfRanges >= 3,
                                   let revRange = Range(match.range(at: 1), in: reviewSection),
                                   let sourceRange = Range(match.range(at: 2), in: reviewSection),
                                   let scoreRange = Range(match.range(at: 3), in: reviewSection) {
                                    
                                    let revNum = String(reviewSection[revRange])
                                    let source = String(reviewSection[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    let score = String(reviewSection[scoreRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    print("\n--- Entry rev\(revNum) ---")
                                    print("RAW SOURCE: '\(source)'")
                                    print("RAW RATING: '\(score)'")
                                    
                                    rawEntries.append((source: source, rating: score))
                                }
                            }
                            
                            // Now process each entry
                            print("\n=== PROCESSED RESULTS ===")
                            
                            for (index, entry) in rawEntries.enumerated() {
                                let cleanedSource = cleanText(entry.source)
                                let cleanedRating = cleanAndExtractRating(entry.rating)
                                
                                print("\(index + 1). \(cleanedSource): \(cleanedRating)")
                            }
                            
                            // Also show what the app's parser would extract
                            print("\n=== WHAT THE APP'S PARSER WOULD EXTRACT ===")
                            print("(Using the WikipediaReviewParser logic)")
                            
                            // Simulate the parser's extraction
                            let appExtracted = extractWithAppParser(reviewSection)
                            print("Total extracted by app: \(appExtracted.count) scores")
                            
                            for (i, score) in appExtracted.enumerated() {
                                print("\(i + 1). \(score.source): \(score.rating)")
                            }
                            
                        } else {
                            print("Failed to create regex")
                        }
                        
                    } else {
                        print("Could not find end of review section")
                    }
                } else {
                    print("Could not find '== Critical reception ==' in wikitext")
                }
                
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

// Simulate the app's parser extraction
func extractWithAppParser(_ text: String) -> [(source: String, rating: String)] {
    var results: [(String, String)] = []
    
    // This mimics the pattern in WikipediaReviewParser.swift
    let pattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n}]+)"
    
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
        return results
    }
    
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    
    for match in matches {
        if match.numberOfRanges >= 4,
           let sourceRange = Range(match.range(at: 2), in: text),
           let ratingRange = Range(match.range(at: 3), in: text) {
            
            let rawSource = String(text[sourceRange])
            let rawRating = String(text[ratingRange])
            
            let cleanedSource = cleanText(rawSource)
            let cleanedRating = cleanAndExtractRating(rawRating)
            
            if !cleanedSource.isEmpty && !cleanedRating.isEmpty {
                results.append((cleanedSource, cleanedRating))
            }
        }
    }
    
    return results
}

// Clean text (remove wiki markup)
func cleanText(_ text: String) -> String {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Remove wiki links
    cleaned = cleaned.replacingOccurrences(
        of: "\\[\\[([^|\\]]+)\\|([^\\]]+)\\]\\]",
        with: "$2",
        options: .regularExpression
    )
    
    cleaned = cleaned.replacingOccurrences(
        of: "\\[\\[([^\\]]+)\\]\\]",
        with: "$1",
        options: .regularExpression
    )
    
    // Remove quotes
    cleaned = cleaned.replacingOccurrences(of: "''", with: "")
    
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}

// Extract and clean rating
func cleanAndExtractRating(_ text: String) -> String {
    var rating = text.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Handle {{Rating|X|Y}} templates
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
    
    // Handle {{rating-Christgau|X}} templates (e.g., {{Rating-Christgau|B+}})
    let christgauPattern = "\\{\\{[Rr]ating-Christgau\\|([^}]+)\\}\\}"
    if let regex = try? NSRegularExpression(pattern: christgauPattern) {
        if let match = regex.firstMatch(in: rating, range: NSRange(rating.startIndex..., in: rating)),
           match.numberOfRanges >= 2,
           let gradeRange = Range(match.range(at: 1), in: rating) {
            
            return String(rating[gradeRange])
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
    
    // Normalize whitespace
    rating = rating.replacingOccurrences(
        of: "\\s+",
        with: " ",
        options: .regularExpression
    )
    
    return rating.trimmingCharacters(in: .whitespacesAndNewlines)
}

// Run the analysis
analyzeRayOfLightReviews()
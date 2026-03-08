import Foundation

struct AlbumReviewScore {
    let source: String
    let rating: String
}

func extractReviewScores(from wikitext: String) -> [AlbumReviewScore] {
    print("\n=== EXTRACTING REVIEW SCORES FROM WIKITEXT ===")
    
    // First, find the review section
    let sectionPatterns = [
        "==\\s*Professional\\s+ratings?\\s*==",
        "==\\s*Critical\\s+reception\\s*==",
        "==\\s*Reception\\s*==",
        "==\\s*Reviews\\s*==",
    ]
    
    var reviewSection: String?
    
    for pattern in sectionPatterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: wikitext, range: NSRange(wikitext.startIndex..., in: wikitext)) {
            let startIndex = wikitext.index(wikitext.startIndex, offsetBy: match.range.location)
            
            // Extract from this header to the next == header or end
            if let nextHeaderRange = wikitext.range(of: "\\n==", options: [.regularExpression], range: startIndex..<wikitext.endIndex) {
                reviewSection = String(wikitext[startIndex..<nextHeaderRange.lowerBound])
            } else {
                reviewSection = String(wikitext[startIndex...])
            }
            break
        }
    }
    
    guard let section = reviewSection else {
        print("No review section found")
        return []
    }
    
    print("Found review section, length: \(section.count) characters")
    
    // Show the raw review section (first 1000 chars)
    print("\n=== RAW REVIEW SECTION (first 1000 chars) ===")
    print(section.prefix(1000))
    
    // Now let's look for tables
    let tableRegex = try! NSRegularExpression(pattern: "\\{\\|.*?\\|\\}", options: [.dotMatchesLineSeparators])
    let tableMatches = tableRegex.matches(in: section, range: NSRange(section.startIndex..., in: section))
    
    print("\n=== FOUND \(tableMatches.count) TABLES IN REVIEW SECTION ===")
    
    var allScores: [AlbumReviewScore] = []
    
    for (i, match) in tableMatches.enumerated() {
        if let range = Range(match.range, in: section) {
            let tableText = String(section[range])
            print("\n--- Table \(i+1) ---")
            print("Table length: \(tableText.count) characters")
            
            // Show first 300 chars of table
            print("First 300 chars:")
            print(tableText.prefix(300))
            
            // Try to extract scores from this table
            let scores = extractScoresFromTable(tableText)
            print("Extracted \(scores.count) scores from this table")
            
            for score in scores {
                print("  - \(score.source): \(score.rating)")
                allScores.append(score)
            }
        }
    }
    
    // Also look for {{Album ratings}} template
    if section.contains("{{Album ratings") || section.contains("{{album ratings") ||
       section.contains("{{Music ratings") || section.contains("{{music ratings") {
        print("\n=== FOUND ALBUM RATINGS TEMPLATE ===")
        
        // Extract using regex
        let pattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n}]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let matches = regex.matches(in: section, range: NSRange(section.startIndex..., in: section))
            print("Found \(matches.count) rev/revScore pairs in template")
            
            for match in matches {
                if match.numberOfRanges >= 4,
                   let revNumber = Range(match.range(at: 1), in: section),
                   let sourceRange = Range(match.range(at: 2), in: section),
                   let ratingRange = Range(match.range(at: 3), in: section) {
                    
                    let revNum = String(section[revNumber])
                    let source = String(section[sourceRange])
                    let rating = String(section[ratingRange])
                    
                    let cleanedSource = cleanText(source)
                    let cleanedRating = cleanText(rating)
                    
                    print("rev\(revNum): \(cleanedSource) → \(cleanedRating)")
                    allScores.append(AlbumReviewScore(source: cleanedSource, rating: cleanedRating))
                }
            }
        }
    }
    
    // Remove duplicates
    var uniqueScores: [AlbumReviewScore] = []
    var seen = Set<String>()
    
    for score in allScores {
        let key = "\(score.source.lowercased()):\(score.rating)"
        if !seen.contains(key) {
            seen.insert(key)
            uniqueScores.append(score)
        }
    }
    
    return uniqueScores
}

func extractScoresFromTable(_ tableText: String) -> [AlbumReviewScore] {
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
                    let source = cleanText(cells[0])
                    let rating = cleanText(cells[1])
                    
                    if !source.isEmpty && !rating.isEmpty && 
                       !source.lowercased().contains("source") &&
                       !source.lowercased().contains("publication") &&
                       !rating.lowercased().contains("rating") &&
                       !rating.lowercased().contains("score") {
                        scores.append(AlbumReviewScore(source: source, rating: rating))
                    }
                }
            } else {
                // Single cell - alternate between source and rating
                if let source = currentSource {
                    let rating = cleanText(cellContent)
                    if !rating.isEmpty && 
                       !rating.lowercased().contains("rating") &&
                       !rating.lowercased().contains("score") {
                        scores.append(AlbumReviewScore(source: source, rating: rating))
                    }
                    currentSource = nil
                } else {
                    let source = cleanText(cellContent)
                    if !source.isEmpty && 
                       !source.lowercased().contains("source") &&
                       !source.lowercased().contains("publication") {
                        currentSource = source
                    }
                }
            }
        }
    }
    
    return scores
}

func cleanText(_ text: String) -> String {
    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Remove citation templates
    cleaned = cleaned.replacingOccurrences(
        of: "\\{\\{cite[^}]*\\}\\}",
        with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    
    // Remove wiki links but preserve display text
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
    
    // Remove ref tags
    cleaned = cleaned.replacingOccurrences(
        of: "<ref[^>]*>.*?</ref>",
        with: "",
        options: .regularExpression
    )
    
    // Remove reference markers
    cleaned = cleaned.replacingOccurrences(
        of: "\\[\\d+\\]",
        with: "",
        options: .regularExpression
    )
    
    // Remove bold/italic markers
    cleaned = cleaned.replacingOccurrences(of: "'''", with: "")
    cleaned = cleaned.replacingOccurrences(of: "''", with: "")
    
    // Normalize whitespace
    cleaned = cleaned.replacingOccurrences(
        of: "\\s+",
        with: " ",
        options: .regularExpression
    )
    
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
}

func fetchAndAnalyzeRayOfLight() {
    print("=== FETCHING RAY OF LIGHT WIKIPEDIA PAGE ===")
    
    let pageTitle = "Ray of Light"
    let encodedTitle = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pageTitle
    let urlString = "https://en.wikipedia.org/w/api.php?action=parse&page=\(encodedTitle)&prop=wikitext&format=json&origin=*"
    
    guard let url = URL(string: urlString) else {
        print("Failed to create URL")
        return
    }
    
    print("Fetching: \(urlString)")
    
    let semaphore = DispatchSemaphore(value: 0)
    
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        defer { semaphore.signal() }
        
        if let error = error {
            print("Error: \(error)")
            return
        }
        
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
                
                // Extract review scores
                let scores = extractReviewScores(from: wikitext)
                
                print("\n=== FINAL RESULTS ===")
                print("Total unique review scores extracted: \(scores.count)")
                
                for (i, score) in scores.enumerated() {
                    print("\(i+1). \(score.source): \(score.rating)")
                }
                
                // Also count how many lines mention "reception" or "review"
                let lines = wikitext.components(separatedBy: .newlines)
                let reviewLines = lines.filter { 
                    $0.lowercased().contains("professional ratings") ||
                    $0.lowercased().contains("critical reception") ||
                    $0.lowercased().contains("reviews from")
                }
                print("\nLines mentioning reviews/reception: \(reviewLines.count)")
                for line in reviewLines.prefix(5) {
                    print("  - \(line)")
                }
                
            } else {
                print("Failed to parse JSON response")
            }
        } catch {
            print("JSON parsing error: \(error)")
        }
    }
    
    task.resume()
    _ = semaphore.wait(timeout: .now() + 30)
}

// Run the analysis
fetchAndAnalyzeRayOfLight()
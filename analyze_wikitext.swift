import Foundation

func dumpRayOfLightReviewSection() {
    print("=== ANALYZING RAY OF LIGHT WIKITEXT ===")
    
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
                        
                        print("\n=== REVIEW SECTION (first 3000 chars) ===")
                        print(reviewSection.prefix(3000))
                        
                        print("\n=== ANALYSIS ===")
                        
                        // Count lines
                        let lines = reviewSection.components(separatedBy: .newlines)
                        print("Total lines in review section: \(lines.count)")
                        
                        // Show lines with tables or ratings
                        print("\nLines containing tables or ratings:")
                        for (i, line) in lines.enumerated() {
                            if line.contains("{|") || line.contains("|}") || line.contains("| ") || 
                               line.contains("||") || line.contains("{{Rating") || line.contains("rev") {
                                print("\(i+1): \(line)")
                            }
                        }
                        
                        // Look for specific patterns
                        print("\n=== SEARCHING FOR SPECIFIC PATTERNS ===")
                        
                        // 1. Look for {{Album ratings}} or {{Music ratings}}
                        if reviewSection.contains("{{Album ratings") || reviewSection.contains("{{Music ratings") {
                            print("Found Album/Music ratings template")
                            
                            // Extract a sample around it
                            if let templateRange = reviewSection.range(of: "\\{\\{[Aa]lbum [Rr]atings.*?\\}\\}\\}", options: .regularExpression) {
                                let template = String(reviewSection[templateRange])
                                print("Template sample (first 500 chars):")
                                print(template.prefix(500))
                            }
                        }
                        
                        // 2. Look for wikitable
                        if let tableStart = reviewSection.range(of: "\\{\\|", options: .regularExpression) {
                            print("\nFound wikitable start at position \(reviewSection.distance(from: reviewSection.startIndex, to: tableStart.lowerBound))")
                            
                            // Try to find the end of the table
                            let afterTableStart = reviewSection[tableStart.lowerBound...]
                            if let tableEnd = afterTableStart.range(of: "\\|\\}", options: .regularExpression) {
                                let tableText = String(afterTableStart[..<tableEnd.upperBound])
                                print("Table length: \(tableText.count) characters")
                                print("First 500 chars of table:")
                                print(tableText.prefix(500))
                            }
                        }
                        
                        // 3. Look for individual review entries
                        print("\n=== INDIVIDUAL REVIEW ENTRIES IN WIKITEXT ===")
                        
                        // Pattern for | revX = ... | revXscore = ...
                        let revPattern = "\\|\\s*rev(\\d+)\\s*=\\s*([^|\\n]+)\\s*\\|\\s*rev\\d+[Ss]core\\s*=\\s*([^|\\n}]+)"
                        
                        if let regex = try? NSRegularExpression(pattern: revPattern, options: .dotMatchesLineSeparators) {
                            let matches = regex.matches(in: reviewSection, range: NSRange(reviewSection.startIndex..., in: reviewSection))
                            print("Found \(matches.count) rev/score pairs")
                            
                            for match in matches {
                                if match.numberOfRanges >= 3,
                                   let revRange = Range(match.range(at: 1), in: reviewSection),
                                   let sourceRange = Range(match.range(at: 2), in: reviewSection),
                                   let scoreRange = Range(match.range(at: 3), in: reviewSection) {
                                    
                                    let revNum = String(reviewSection[revRange])
                                    let source = String(reviewSection[sourceRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    let score = String(reviewSection[scoreRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    print("rev\(revNum): \(source) → \(score)")
                                }
                            }
                        }
                        
                        // 4. Look for table rows with || separator
                        print("\n=== TABLE ROWS WITH || SEPARATOR ===")
                        let tableRowPattern = "\\|\\s*([^|\\n]+)\\s*\\|\\|\\s*([^|\\n]+)"
                        if let regex = try? NSRegularExpression(pattern: tableRowPattern) {
                            let matches = regex.matches(in: reviewSection, range: NSRange(reviewSection.startIndex..., in: reviewSection))
                            print("Found \(matches.count) table rows with ||")
                            
                            for (i, match) in matches.prefix(10).enumerated() {
                                if match.numberOfRanges >= 3,
                                   let col1Range = Range(match.range(at: 1), in: reviewSection),
                                   let col2Range = Range(match.range(at: 2), in: reviewSection) {
                                    
                                    let col1 = String(reviewSection[col1Range]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    let col2 = String(reviewSection[col2Range]).trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    print("Row \(i+1): \(col1) || \(col2)")
                                }
                            }
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

dumpRayOfLightReviewSection()
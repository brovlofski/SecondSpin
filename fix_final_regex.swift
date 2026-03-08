import Foundation

// Test to fix the final regex issue - capturing full {{Rating|X|Y}} templates

func testFinalRegexFix() {
    print("=== Testing Final Regex Fix ===")
    
    // Sample text from Ray of Light wikitext
    let sampleText = """
| rev1 = ''[[Chicago Tribune]]''
| rev1Score = {{Rating|3.5|4}}<ref>{{cite news|last=Kot|first=Greg|author-link=Greg Kot|date=March 1, 1998|url=https://www.chicagotribune.com/1998/03/01/new-material-girl/|title=New-Material Girl|newspaper=[[Chicago Tribune]]|access-date=September 22, 2015|archive-date=March 4, 2016|archive-url=https://web.archive.org/web/20160304110827/http://articles.chicagotribune.com/1998-03-01/news/9803010300_1_shep-pettibone-pop-stars-william-orbit|url-status=live}}</ref>
| rev2 = ''[[Entertainment Weekly]]''
| rev2Score = A−<ref name="ew" />
| rev3 = ''[[The Guardian]]''
| rev3Score = {{Rating|4|5}}<ref name="The Guardian Review">{{cite news|last=Sullivan|first=Caroline|title=Madonna: ''Ray of Light'' (WEA)|newspaper=[[The Guardian]]|date=February 27, 1998|page=18|issn=0261-3077}}</ref>
| rev4 = ''[[NME]]''
| rev4Score = 8/10<ref>{{cite magazine |url=https://www.nme.com/reviews/reviews/19980101000248reviews.html|title=Madonna – ''Ray of Light'' |last=Moody |first=Paul |magazine=[[NME]] |page=43|date=February 28, 1998|access-date=March 27, 2020|archive-url=https://web.archive.org/web/20000817192218/http://www.nme.com/reviews/reviews/19980101000248reviews.html|archive-date=August 17, 2000|url-status=dead}}</ref>
| rev5 = ''[[Now (newspaper)|Now]]''
| rev5score = {{Rating|2|5}}<ref>{{cite web|url=http://www.nowtoronto.com/issues/17/26/Ent/discnow.html|title=Mediocre Madonna, awesome Ian Brown|newspaper=[[Now (newspaper)|Now]]|last=Perlich|first=Tim|date=March 4, 1998|archive-url=https://web.archive.org/web/20070926224553/http://www.nowtoronto.com/issues/17/26/Ent/discnow.html |access-date=June 18, 2025 |archive-date=September 26, 2007 }}</ref>
"""
    
    print("\n--- Testing CURRENT problematic pattern ---")
    let currentPattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n]+?)(?=(?:<ref|\\||\\}\\}|$))"
    
    if let regex = try? NSRegularExpression(pattern: currentPattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Current pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                let rating = String(sampleText[ratingRange])
                print("rev\(revNum): Rating='\(rating)'")
            }
        }
    }
    
    print("\n--- Testing NEW pattern that handles templates with pipes ---")
    
    // NEW pattern: capture everything until }} or <ref or | or end, but allow pipes inside {{...}}
    // The key insight: we need to match {{...}} templates as a single unit
    // Let's try a two-step approach: first match the pattern, then extract templates
    
    // Pattern 1: Match revX = ... | revXscore = ... with better handling of templates
    // We'll use a more permissive pattern and then post-process
    let newPattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n}]+(?:\\}[^|\\n}]+)*)(?=(?:<ref|\\||$))"
    
    if let regex = try? NSRegularExpression(pattern: newPattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("New pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                let rating = String(sampleText[ratingRange])
                print("rev\(revNum): Rating='\(rating)'")
            }
        }
    }
    
    print("\n--- Testing BEST pattern: handle {{...}} templates properly ---")
    
    // Actually, let's think differently. The issue is that [^|\\n]+ stops at pipes.
    // But {{Rating|3.5|4}} contains pipes. We need to allow pipes if they're inside {{...}}
    // We can't do balanced braces with regex, but we can approximate for this specific case
    
    // Pattern that allows pipes if they're part of {{...}} template
    // This is tricky. Instead, let's capture everything until }}<ref or }} | or }} $
    let bestPattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*((?:[^{}|\\n]|\\{\\{[^{}]*\\}\\})*?)(?=(?:<ref|\\||$))"
    
    if let regex = try? NSRegularExpression(pattern: bestPattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Best pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                let rating = String(sampleText[ratingRange])
                print("rev\(revNum): Rating='\(rating)'")
            }
        }
    }
    
    print("\n--- Testing SIMPLEST fix: capture until }}<ref ---")
    
    // Actually, looking at the data, all ratings either:
    // 1. Simple text: "A−" or "8/10"
    // 2. {{Rating|X|Y}} template
    // 3. {{Rating|X|Y}}<ref...
    
    // So we can capture: (non-pipe, non-brace chars OR {{[^}]*}} ) until <ref or | or end
    let simplePattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*((?:[^{}|\\n]|\\{\\{[^{}]+?\\}\\})+?)(?=(?:<ref|\\||$))"
    
    if let regex = try? NSRegularExpression(pattern: simplePattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Simple pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                let rating = String(sampleText[ratingRange])
                print("rev\(revNum): Rating='\(rating)'")
            }
        }
    }
    
    print("\n--- Testing WORKING solution: two-step approach ---")
    
    // Actually, the cleanest solution: First extract the rev/score pairs with a simple pattern
    // that captures everything until the next pipe or end of line, then clean up
    let workingPattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n]+)"
    
    if let regex = try? NSRegularExpression(pattern: workingPattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Working pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                var rating = String(sampleText[ratingRange])
                
                print("\nrev\(revNum) RAW: '\(rating)'")
                
                // Post-process: truncate at "<ref" if present
                if let refRange = rating.range(of: "<ref") {
                    rating = String(rating[..<refRange.lowerBound])
                }
                
                // Also truncate at "}}" if it's followed by non-template content?
                // Actually {{Rating|3.5|4}}<ref> should become {{Rating|3.5|4}}
                // But we already removed <ref, so we're left with {{Rating|3.5|4}}
                
                print("rev\(revNum) CLEANED: '\(rating)'")
            }
        }
    }
    
    print("\n--- Testing FINAL solution: comprehensive pattern ---")
    
    // Final pattern: capture everything, then clean
    let finalPattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|]+)"
    
    if let regex = try? NSRegularExpression(pattern: finalPattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Final pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                var rating = String(sampleText[ratingRange])
                
                print("\nrev\(revNum) FULL RAW: '\(rating)'")
                
                // Clean up: remove everything after first <ref
                if let refRange = rating.range(of: "<ref") {
                    rating = String(rating[..<refRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Also handle case where rating ends with }} followed by text
                // Keep only up to }} if it's a template
                if rating.contains("{{") && rating.contains("}}") {
                    // Find last }} and keep everything up to it
                    if let endRange = rating.range(of: "}}", options: .backwards) {
                        rating = String(rating[...endRange.upperBound])
                    }
                }
                
                rating = rating.trimmingCharacters(in: .whitespacesAndNewlines)
                print("rev\(revNum) FINAL: '\(rating)'")
            }
        }
    }
}

testFinalRegexFix()
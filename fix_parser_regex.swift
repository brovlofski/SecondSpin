import Foundation

// Test to fix the WikipediaReviewParser regex patterns
func testRegexPatterns() {
    print("=== Testing Regex Patterns for Wikipedia Parser ===")
    
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
"""
    
    print("\nSample text length: \(sampleText.count)")
    print("\n--- Testing CURRENT pattern from WikipediaReviewParser ---")
    
    // Current pattern from WikipediaReviewParser.swift
    let currentPattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n}]+)"
    
    if let regex = try? NSRegularExpression(pattern: currentPattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Current pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let sourceRange = Range(match.range(at: 2), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                let source = String(sampleText[sourceRange])
                let rating = String(sampleText[ratingRange])
                
                print("rev\(revNum): Source='\(source)', Rating='\(rating)'")
            }
        }
    }
    
    print("\n--- Testing IMPROVED pattern (handles {{Rating|X|Y}} templates) ---")
    
    // Improved pattern: capture everything until }} or ref tag or next |
    // We need to handle nested templates properly
    let improvedPattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|\\n]+?)(?=(?:<ref|\\||\\}\\}|$))"
    
    if let regex = try? NSRegularExpression(pattern: improvedPattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Improved pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let sourceRange = Range(match.range(at: 2), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                let source = String(sampleText[sourceRange])
                let rating = String(sampleText[ratingRange])
                
                print("rev\(revNum): Source='\(source)', Rating='\(rating)'")
            }
        }
    }
    
    print("\n--- Testing BEST pattern (handles templates with pipes) ---")
    
    // Even better: we need to count braces to handle nested templates
    // But for simplicity, let's capture until }} followed by optional ref
    let bestPattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*(.*?)(?=(?:\\}\\}|<ref|\\||$))"
    
    if let regex = try? NSRegularExpression(pattern: bestPattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Best pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let sourceRange = Range(match.range(at: 2), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                let source = String(sampleText[sourceRange])
                let rating = String(sampleText[ratingRange])
                
                print("rev\(revNum): Source='\(source)', Rating='\(rating)'")
            }
        }
    }
    
    print("\n--- Testing SIMPLE fix: capture until }} or <ref ---")
    
    // Simple fix: capture until }} or <ref
    let simplePattern = "\\|\\s*rev(\\d+)\\s*=\\s*['\"]?([^|\\n]+?)['\"]?\\s*\\|\\s*rev\\1[Ss]core\\s*=\\s*([^|}]+?(?:\\}\\}[^|}]*?)?)(?=<ref|\\||$)"
    
    if let regex = try? NSRegularExpression(pattern: simplePattern, options: [.dotMatchesLineSeparators]) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Simple pattern found \(matches.count) matches")
        
        for match in matches {
            if match.numberOfRanges >= 4,
               let revRange = Range(match.range(at: 1), in: sampleText),
               let sourceRange = Range(match.range(at: 2), in: sampleText),
               let ratingRange = Range(match.range(at: 3), in: sampleText) {
                
                let revNum = String(sampleText[revRange])
                let source = String(sampleText[sourceRange])
                let rating = String(sampleText[ratingRange])
                
                print("rev\(revNum): Source='\(source)', Rating='\(rating)'")
            }
        }
    }
    
    print("\n--- Testing EXTRACTION with post-processing ---")
    
    // Actually, maybe we should extract the full template and then parse it separately
    // Let's try to extract the entire {{Rating|X|Y}} template
    let templatePattern = "\\{\\{[Rr]ating\\|([^|}]+)\\|([^|}]+)\\}\\}"
    
    if let regex = try? NSRegularExpression(pattern: templatePattern) {
        let matches = regex.matches(in: sampleText, range: NSRange(sampleText.startIndex..., in: sampleText))
        print("Found \(matches.count) {{Rating|X|Y}} templates")
        
        for match in matches {
            if match.numberOfRanges >= 3,
               let numRange = Range(match.range(at: 1), in: sampleText),
               let denomRange = Range(match.range(at: 2), in: sampleText) {
                
                let numerator = String(sampleText[numRange])
                let denominator = String(sampleText[denomRange])
                
                print("Rating template: \(numerator)/\(denominator)")
            }
        }
    }
}

testRegexPatterns()
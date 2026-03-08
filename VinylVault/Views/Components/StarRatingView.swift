//
//  StarRatingView.swift
//  VinylVault
//
//  Component for displaying star ratings from Wikipedia review scores.
//

import SwiftUI
import Foundation

struct StarRatingView: View {
    let rating: Double
    let maxRating: Double
    let starSize: CGFloat = 16
    
    // Use the original scale for stars, but cap at 10 for visual display
    private var displayMaxStars: Int {
        if maxRating <= 0 { return 5 }
        let rounded = Int(maxRating.rounded())
        // Cap at 10 stars maximum for visual display
        return min(max(rounded, 1), 10)
    }
    
    // Scale the rating to the display star count
    private var scaledRating: Double {
        if maxRating <= 0 { return 0 }
        return (rating / maxRating) * Double(displayMaxStars)
    }
    
    private var filledStars: Int {
        Int(scaledRating.rounded(.down))
    }
    
    private var hasHalfStar: Bool {
        let fractionalPart = scaledRating - Double(filledStars)
        return fractionalPart >= 0.25
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<displayMaxStars, id: \.self) { index in
                if index < filledStars {
                    Image(systemName: "star.fill")
                        .font(.system(size: starSize))
                        .foregroundColor(.yellow)
                } else if index == filledStars && hasHalfStar {
                    Image(systemName: "star.leadinghalf.fill")
                        .font(.system(size: starSize))
                        .foregroundColor(.yellow)
                } else {
                    Image(systemName: "star")
                        .font(.system(size: starSize))
                        .foregroundColor(.gray.opacity(0.4))
                }
            }
            
            // Show the original rating as text
            if maxRating == 5.0 {
                // For 5-point scales, show simplified "3.5/5"
                Text("\(rating, specifier: "%.1f")/\(maxRating, specifier: "%.0f")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // For other scales, show the full rating
                Text("\(rating, specifier: "%.1f")/\(maxRating, specifier: "%.1f")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    /// Parses star rating string like "3.5/5" or "7/10" into (rating, maxRating)
    static func parseStarRating(_ ratingString: String) -> (Double, Double)? {
        let ratingString = ratingString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try pattern X/Y where X and Y are numbers
        let slashPattern = "^\\s*([0-9./]+)\\s*/\\s*([0-9./]+)\\s*$"
        if let regex = try? NSRegularExpression(pattern: slashPattern, options: []),
           let match = regex.firstMatch(in: ratingString, range: NSRange(ratingString.startIndex..., in: ratingString)),
           match.numberOfRanges >= 3,
           let numeratorRange = Range(match.range(at: 1), in: ratingString),
           let denominatorRange = Range(match.range(at: 2), in: ratingString) {
            
            let numeratorStr = String(ratingString[numeratorRange])
            let denominatorStr = String(ratingString[denominatorRange])
            
            if let numerator = Double(numeratorStr),
               let denominator = Double(denominatorStr),
               denominator > 0 {
                return (numerator, denominator)
            }
        }
        
        // Try pattern like "3.5 stars" or "3.5/5 stars"
        let starPattern = "^\\s*([0-9./]+)\\s*(?:/\\s*([0-9./]+)\\s*)?stars?\\s*$"
        if let regex = try? NSRegularExpression(pattern: starPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: ratingString, range: NSRange(ratingString.startIndex..., in: ratingString)),
           match.numberOfRanges >= 2,
           let ratingRange = Range(match.range(at: 1), in: ratingString) {
            
            let ratingStr = String(ratingString[ratingRange])
            
            // If we have explicit denominator in match group 2
            if match.numberOfRanges >= 3,
               let denominatorRange = Range(match.range(at: 2), in: ratingString) {
                let denominatorStr = String(ratingString[denominatorRange])
                if let numerator = Double(ratingStr),
                   let denominator = Double(denominatorStr),
                   denominator > 0 {
                    return (numerator, denominator)
                }
            }
            
            // If only rating number is given, assume it's out of 5
            if let ratingValue = Double(ratingStr) {
                return (ratingValue, 5.0)
            }
        }
        
        // Try decimal number alone (assume out of 5)
        let decimalPattern = "^\\s*([0-9]+(?:\\.[0-9]+)?)\\s*$"
        if let regex = try? NSRegularExpression(pattern: decimalPattern, options: []),
           let match = regex.firstMatch(in: ratingString, range: NSRange(ratingString.startIndex..., in: ratingString)),
           match.numberOfRanges >= 2,
           let ratingRange = Range(match.range(at: 1), in: ratingString) {
            
            let ratingStr = String(ratingString[ratingRange])
            if let ratingValue = Double(ratingStr) {
                // Check if it's likely a percentage (e.g., 85, 90)
                if ratingValue >= 50 && ratingValue <= 100 {
                    return (ratingValue, 100.0)
                } else if ratingValue <= 10 && ratingValue >= 0 {
                    return (ratingValue, 10.0)
                } else {
                    return (ratingValue, 5.0)
                }
            }
        }
        
        // Try percentage pattern like "85%"
        let percentPattern = "^\\s*([0-9]+(?:\\.[0-9]+)?)%\\s*$"
        if let regex = try? NSRegularExpression(pattern: percentPattern, options: []),
           let match = regex.firstMatch(in: ratingString, range: NSRange(ratingString.startIndex..., in: ratingString)),
           match.numberOfRanges >= 2,
           let percentRange = Range(match.range(at: 1), in: ratingString) {
            
            let percentStr = String(ratingString[percentRange])
            if let percentValue = Double(percentStr) {
                return (percentValue, 100.0)
            }
        }
        
        return nil
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Star Rating Examples")
            .font(.headline)
        
        VStack(spacing: 10) {
            StarRatingView(rating: 3.5, maxRating: 4)  // 3.5/4 scale
            StarRatingView(rating: 4.0, maxRating: 5)  // 4/5 scale
            StarRatingView(rating: 2.5, maxRating: 5)
            StarRatingView(rating: 5.0, maxRating: 5)
            StarRatingView(rating: 7.0, maxRating: 10) // 7/10 scale
            StarRatingView(rating: 8.5, maxRating: 10) // 8.5/10 scale
        }
        
        Divider()
        
        Text("Parsing Examples")
            .font(.headline)
        
        VStack(alignment: .leading, spacing: 10) {
            let examples = [
                "3.5/4",
                "4/5",
                "7/10",
                "85%",
                "9.2/10",
                "3.5 stars",
                "4.0",
                "8.5/10 stars"
            ]
            
            ForEach(examples, id: \.self) { example in
                HStack {
                    Text(example)
                        .font(.caption)
                    Spacer()
                    if let parsed = StarRatingView.parseStarRating(example) {
                        StarRatingView(rating: parsed.0, maxRating: parsed.1)
                    } else {
                        Text("Not parsable")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    .padding()
}
//
//  PitchforkBadgeView.swift
//  VinylVault
//
//  Badge view for albums that appeared on Pitchfork's year-end "Best Albums" lists
//

import SwiftUI

struct PitchforkBadgeView: View {
    let badge: PitchforkBadge
    let compact: Bool
    
    init(badge: PitchforkBadge, compact: Bool = false) {
        self.badge = badge
        self.compact = compact
    }
    
    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            // Pitchfork icon
            pitchforkIcon
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .foregroundColor(.white)
            
            // Badge text
            Text(compact ? badge.shortDisplayText : badge.displayText)
                .font(.system(size: compact ? 11 : 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(
            RoundedRectangle(cornerRadius: compact ? 6 : 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.24, blue: 0.29), // Pitchfork red
                            Color(red: 0.85, green: 0.15, blue: 0.20)  // Darker red
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
        )
    }
    
    // Custom Pitchfork icon using SF Symbols styled as a pitchfork
    private var pitchforkIcon: some View {
        // Using a trident/fork symbol to represent Pitchfork
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .rotationEffect(.degrees(0))
            .symbolRenderingMode(.monochrome)
    }
}

// MARK: - Alternative Pitchfork Icon using Text
struct PitchforkTextIcon: View {
    var body: some View {
        Text("⋔") // Trident-like character
            .font(.system(size: 14, weight: .bold))
    }
}

// MARK: - Pitchfork Badge Card (for detail view)
struct PitchforkBadgeCard: View {
    let badge: PitchforkBadge
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon
            HStack(spacing: 8) {
                Image(systemName: "rosette")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(red: 0.98, green: 0.24, blue: 0.29))
                
                Text("Pitchfork Acclaim")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            // Badge display
            PitchforkBadgeView(badge: badge, compact: false)
            
            // Description
            Text("This album was ranked #\(badge.rank) on Pitchfork's Best Albums of \(badge.year) list.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 0.98, green: 0.24, blue: 0.29).opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Preview
#Preview("Badge - Compact") {
    VStack(spacing: 20) {
        PitchforkBadgeView(
            badge: PitchforkBadge(year: "2023", rank: 1, coverURL: nil),
            compact: true
        )
        
        PitchforkBadgeView(
            badge: PitchforkBadge(year: "2023", rank: 15, coverURL: nil),
            compact: true
        )
        
        PitchforkBadgeView(
            badge: PitchforkBadge(year: "2016", rank: 10, coverURL: nil),
            compact: true
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Badge - Full") {
    VStack(spacing: 20) {
        PitchforkBadgeView(
            badge: PitchforkBadge(year: "2023", rank: 1, coverURL: nil),
            compact: false
        )
        
        PitchforkBadgeView(
            badge: PitchforkBadge(year: "2023", rank: 15, coverURL: nil),
            compact: false
        )
        
        PitchforkBadgeView(
            badge: PitchforkBadge(year: "2016", rank: 10, coverURL: nil),
            compact: false
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}

#Preview("Badge Card") {
    PitchforkBadgeCard(
        badge: PitchforkBadge(year: "2023", rank: 1, coverURL: nil)
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
//
//  ReviewCardView.swift
//  VinylVault
//
//  Card view for displaying album reviews from CritiqueBrainz
//

import SwiftUI

struct ReviewCardView: View {
    let review: AlbumReview
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Author name and date
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(formatDate(review.createdDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Vote counts (if any)
                if review.votesPositiveCount > 0 || review.votesNegativeCount > 0 {
                    HStack(spacing: 8) {
                        if review.votesPositiveCount > 0 {
                            Label("\(review.votesPositiveCount)", systemImage: "hand.thumbsup.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        if review.votesNegativeCount > 0 {
                            Label("\(review.votesNegativeCount)", systemImage: "hand.thumbsdown.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            
            // Review text
            Text(isExpanded ? review.text : review.truncatedText)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(isExpanded ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)
            
            // Read more/less button and external link
            HStack {
                if review.text.count > 200 {
                    Button(action: onToggle) {
                        Text(isExpanded ? "Show Less" : "Read More")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
                
                // External source link
                if let sourceUrl = review.sourceUrl, let url = URL(string: sourceUrl) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text("View Original")
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatDate(_ dateString: String) -> String {
        // Parse date like "Fri, 13 Apr 2007 00:00:00 GMT"
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        if let date = formatter.date(from: dateString) {
            let outputFormatter = DateFormatter()
            outputFormatter.dateStyle = .medium
            return outputFormatter.string(from: date)
        }
        
        return dateString
    }
}

#Preview {
    VStack(spacing: 16) {
        ReviewCardView(
            review: AlbumReview(
                id: "1",
                text: "This is an amazing album with incredible production quality. The songwriting is top-notch and every track flows perfectly into the next. A true masterpiece of modern music that will stand the test of time.",
                rating: nil,
                user: AlbumReview.ReviewUser(displayName: "John Doe", userId: "123"),
                source: "BBC Music",
                sourceUrl: "https://example.com",
                createdDate: "Fri, 13 Apr 2007 00:00:00 GMT",
                votesPositiveCount: 15,
                votesNegativeCount: 2
            ),
            isExpanded: false,
            onToggle: {}
        )
        
        ReviewCardView(
            review: AlbumReview(
                id: "2",
                text: "Short review here.",
                rating: nil,
                user: AlbumReview.ReviewUser(displayName: "Jane Smith", userId: "456"),
                source: nil,
                sourceUrl: nil,
                createdDate: "Mon, 20 Jan 2020 12:00:00 GMT",
                votesPositiveCount: 0,
                votesNegativeCount: 0
            ),
            isExpanded: false,
            onToggle: {}
        )
    }
    .padding()
}
//
//  MusicBrainzModels.swift
//  VinylVault
//
//  Models for MusicBrainz and CritiqueBrainz API responses
//

import Foundation

// MARK: - MusicBrainz Rating
struct MusicBrainzRating: Codable {
    let value: Double?
    let votesCount: Int
    
    enum CodingKeys: String, CodingKey {
        case value
        case votesCount = "votes-count"
    }
    
    var displayRating: String {
        guard let value = value else { return "No rating" }
        return String(format: "%.1f/5", value)
    }
}

// MARK: - MusicBrainz Genre
struct MusicBrainzGenre: Codable, Identifiable {
    let id: String
    let name: String
    let count: Int
    let disambiguation: String
}

// MARK: - MusicBrainz Release Group Search
struct MusicBrainzSearchResponse: Codable {
    let releaseGroups: [MusicBrainzReleaseGroup]
    let count: Int
    let offset: Int
    
    enum CodingKeys: String, CodingKey {
        case releaseGroups = "release-groups"
        case count
        case offset
    }
}

struct MusicBrainzReleaseGroup: Codable {
    let id: String
    let title: String
    let primaryType: String?
    let artistCredit: [ArtistCredit]?
    let score: Int?
    let rating: MusicBrainzRating?
    let genres: [MusicBrainzGenre]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case primaryType = "primary-type"
        case artistCredit = "artist-credit"
        case score
        case rating
        case genres
    }
    
    struct ArtistCredit: Codable {
        let name: String
        let artist: Artist?
        
        struct Artist: Codable {
            let id: String
            let name: String
        }
    }
    
    var artistName: String {
        artistCredit?.first?.name ?? ""
    }
}

// MARK: - CritiqueBrainz Review
struct CritiqueBrainzResponse: Codable {
    let reviews: [AlbumReview]
    let count: Int
    let offset: Int
    let limit: Int
}

struct AlbumReview: Codable, Identifiable {
    let id: String
    let text: String
    let rating: Int?
    let user: ReviewUser
    let source: String?
    let sourceUrl: String?
    let createdDate: String
    let votesPositiveCount: Int
    let votesNegativeCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case rating
        case user
        case source
        case sourceUrl = "source_url"
        case createdDate = "created"
        case votesPositiveCount = "votes_positive_count"
        case votesNegativeCount = "votes_negative_count"
    }
    
    struct ReviewUser: Codable {
        let displayName: String
        let userId: String
        
        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case userId = "user_ref"
        }
    }
    
    var truncatedText: String {
        if text.count > 200 {
            let index = text.index(text.startIndex, offsetBy: 200)
            return String(text[..<index]) + "..."
        }
        return text
    }
    
    var authorName: String {
        if let source = source, !source.isEmpty {
            return source
        }
        return user.displayName
    }
}

// MARK: - Cached MusicBrainz Data
struct CachedMusicBrainzData: Codable {
    let mbid: String
    let rating: MusicBrainzRating?
    let genres: [MusicBrainzGenre]
    let cachedDate: Date
    
    var isExpired: Bool {
        // Cache expires after 7 days
        Calendar.current.dateComponents([.day], from: cachedDate, to: Date()).day ?? 0 > 7
    }
}
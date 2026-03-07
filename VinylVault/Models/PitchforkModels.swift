//
//  PitchforkModels.swift
//  VinylVault
//
//  Models for Pitchfork year-end list data from AOTY API
//

import Foundation

// MARK: - Pitchfork Year-End List Entry
struct PitchforkYearEndEntry: Codable, Identifiable {
    let artist: String
    let album: String
    let rank: Int
    let albumCover: String
    
    var id: String { "\(artist)-\(album)-\(rank)" }
    
    enum CodingKeys: String, CodingKey {
        case artist
        case album
        case rank
        case albumCover = "album-cover"
    }
}

// MARK: - Artist Year-End Appearances
struct PitchforkArtistYearEndData: Codable {
    let entries: [String: PitchforkYearEndEntry] // Key is year
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.entries = try container.decode([String: PitchforkYearEndEntry].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }
    
    // Get the best (lowest rank number) appearance
    var bestAppearance: (year: String, entry: PitchforkYearEndEntry)? {
        entries.min { $0.value.rank < $1.value.rank }
            .map { (year: $0.key, entry: $0.value) }
    }
}

// MARK: - Pitchfork Badge Data
struct PitchforkBadge: Identifiable {
    let id = UUID()
    let year: String
    let rank: Int
    let coverURL: String?
    
    var displayText: String {
        "Pitchfork Best of \(year) #\(rank)"
    }
    
    var shortDisplayText: String {
        "Best of \(year) #\(rank)"
    }
}
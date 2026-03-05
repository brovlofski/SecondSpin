//
//  Release.swift
//  VinylVault
//
//  Data model for vinyl release
//

import Foundation
import SwiftData

@Model
final class Release {
    @Attribute(.unique) var discogsId: Int
    var title: String
    var artist: String
    var year: Int
    var label: String
    var coverImageURL: String
    var thumbnailImageURL: String
    var allImageURLs: [String]
    var genres: [String]
    var styles: [String]
    var format: String
    /// Descriptions from Discogs formats array, e.g. ["LP", "Album", "Repress", "Club Edition"]
    var formatDescriptions: [String]
    var country: String?
    var barcode: String?
    var dateAdded: Date
    var tracklist: [Track]
    /// Verified direct Spotify album URL (nil = not yet resolved)
    var spotifyAlbumURL: String?
    /// Verified direct Apple Music album URL (nil = not yet resolved)
    var appleMusicAlbumURL: String?
    /// True once the streaming links have been searched and cached
    var streamingLinksVerified: Bool

    @Relationship(deleteRule: .cascade, inverse: \Copy.release)
    var copies: [Copy]
    
    @Relationship(inverse: \RecordList.releases)
    var lists: [RecordList]
    
    init(
        discogsId: Int,
        title: String,
        artist: String,
        year: Int,
        label: String,
        coverImageURL: String,
        thumbnailImageURL: String,
        allImageURLs: [String] = [],
        genres: [String],
        styles: [String],
        format: String,
        formatDescriptions: [String] = [],
        country: String? = nil,
        barcode: String? = nil,
        dateAdded: Date = Date(),
        tracklist: [Track] = []
    ) {
        self.discogsId = discogsId
        self.title = title
        self.artist = artist
        self.year = year
        self.label = label
        self.coverImageURL = coverImageURL
        self.thumbnailImageURL = thumbnailImageURL
        self.allImageURLs = allImageURLs.isEmpty ? (coverImageURL.isEmpty ? [] : [coverImageURL]) : allImageURLs
        self.genres = genres
        self.styles = styles
        self.format = format
        self.formatDescriptions = formatDescriptions
        self.country = country
        self.barcode = barcode
        self.dateAdded = dateAdded
        self.tracklist = tracklist
        self.spotifyAlbumURL = nil
        self.appleMusicAlbumURL = nil
        self.streamingLinksVerified = false
        self.copies = []
        self.lists = []
    }
    
    var copyCount: Int {
        copies.count
    }

    /// Full human-readable format string, e.g. "Vinyl · LP · Album · Repress"
    var fullFormatDisplay: String {
        let parts = ([format] + formatDescriptions).filter { !$0.isEmpty }
        // Deduplicate while preserving order
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        return unique.joined(separator: " · ")
    }
}

// Track model for tracklist
struct Track: Codable, Hashable {
    let position: String
    let title: String
    let duration: String?
    
    init(position: String, title: String, duration: String? = nil) {
        self.position = position
        self.title = title
        self.duration = duration
    }
}
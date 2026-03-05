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
    var country: String?
    var barcode: String?
    var dateAdded: Date
    var tracklist: [Track]
    
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
        self.country = country
        self.barcode = barcode
        self.dateAdded = dateAdded
        self.tracklist = tracklist
        self.copies = []
        self.lists = []
    }
    
    var copyCount: Int {
        copies.count
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
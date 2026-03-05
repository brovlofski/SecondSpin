//
//  RecordList.swift
//  VinylVault
//
//  Data model for user-defined lists
//

import Foundation
import SwiftData

@Model
final class RecordList {
    @Attribute(.unique) var id: UUID
    var name: String
    var listDescription: String
    var dateCreated: Date
    var orderIndex: Int
    
    var releases: [Release]
    
    init(
        name: String,
        listDescription: String = "",
        dateCreated: Date = Date(),
        orderIndex: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.listDescription = listDescription
        self.dateCreated = dateCreated
        self.orderIndex = orderIndex
        self.releases = []
    }
}
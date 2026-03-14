//
//  RecordList.swift
//  VinylVault
//
//  Data model for user-defined lists
//

import Foundation
import SwiftData

enum SystemListType: String, Codable {
    case listenLater = "listenLater"
    // Add more system list types here in the future
}

@Model
final class RecordList {
    @Attribute(.unique) var id: UUID
    var name: String
    var listDescription: String
    var dateCreated: Date
    var orderIndex: Int
    var isSystemList: Bool
    var systemListType: SystemListType?
    
    var releases: [Release]
    
    init(
        name: String,
        listDescription: String = "",
        dateCreated: Date = Date(),
        orderIndex: Int = 0,
        isSystemList: Bool = false,
        systemListType: SystemListType? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.listDescription = listDescription
        self.dateCreated = dateCreated
        self.orderIndex = orderIndex
        self.isSystemList = isSystemList
        self.systemListType = systemListType
        self.releases = []
    }
    
    // Convenience initializer for system lists
    static func createSystemList(type: SystemListType, name: String, description: String = "") -> RecordList {
        return RecordList(
            name: name,
            listDescription: description,
            dateCreated: Date(),
            orderIndex: -1, // System lists will be sorted to the top
            isSystemList: true,
            systemListType: type
        )
    }
}

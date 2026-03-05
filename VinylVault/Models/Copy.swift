//
//  Copy.swift
//  VinylVault
//
//  Data model for individual vinyl copy
//

import Foundation
import SwiftData

@Model
final class Copy {
    var id: UUID
    var purchasePrice: Double?
    var condition: String
    var notes: String
    var dateAdded: Date
    
    var release: Release?
    
    init(
        purchasePrice: Double? = nil,
        condition: String = "Mint",
        notes: String = "",
        dateAdded: Date = Date()
    ) {
        self.id = UUID()
        self.purchasePrice = purchasePrice
        self.condition = condition
        self.notes = notes
        self.dateAdded = dateAdded
    }
}

// Condition options
enum VinylCondition: String, CaseIterable {
    case mint = "Mint (M)"
    case nearMint = "Near Mint (NM)"
    case veryGoodPlus = "Very Good Plus (VG+)"
    case veryGood = "Very Good (VG)"
    case goodPlus = "Good Plus (G+)"
    case good = "Good (G)"
    case fair = "Fair (F)"
    case poor = "Poor (P)"
}
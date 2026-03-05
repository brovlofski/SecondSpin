//
//  BackupService.swift
//  VinylVault
//
//  Export / Import collection backup (text-only, no image binary data)
//
//  Backup file format: JSON wrapped in a versioned envelope.
//  Filename pattern:   secondspin-app-data-{ISO8601-timestamp}.backup
//
//  Image URLs are stored as plain strings so the app can re-download
//  artwork on demand — no image bytes are ever written to the file.
//

import Foundation
import SwiftData

// MARK: - Transfer DTOs (Codable, image-free)

struct CopyBackupDTO: Codable {
    var id: UUID
    var purchasePrice: Double?
    var condition: String
    var notes: String
    var dateAdded: Date
}

struct TrackBackupDTO: Codable {
    var position: String
    var title: String
    var duration: String?
}

struct ReleaseBackupDTO: Codable {
    var discogsId: Int
    var title: String
    var artist: String
    var year: Int
    var label: String
    // Only the URL strings are stored — no actual image data.
    var coverImageURL: String
    var thumbnailImageURL: String
    var allImageURLs: [String]
    var genres: [String]
    var styles: [String]
    var format: String
    var country: String?
    var barcode: String?
    var dateAdded: Date
    var tracklist: [TrackBackupDTO]
    var copies: [CopyBackupDTO]
}

struct ListBackupDTO: Codable {
    var id: UUID
    var name: String
    var listDescription: String
    var dateCreated: Date
    var orderIndex: Int
    /// References releases by their Discogs ID (no embedded release data).
    var releaseDiscogsIds: [Int]
}

struct AppBackup: Codable {
    var version: Int
    var exportedAt: Date
    var releases: [ReleaseBackupDTO]
    var lists: [ListBackupDTO]

    static let currentVersion = 1
}

// MARK: - Import result

struct ImportResult {
    let releasesImported: Int
    let releasesSkipped: Int
    let listsImported: Int
    let listsSkipped: Int

    var summary: String {
        var parts: [String] = []
        parts.append(
            "\(releasesImported) release\(releasesImported == 1 ? "" : "s") imported"
        )
        if releasesSkipped > 0 {
            parts.append("\(releasesSkipped) skipped (already in collection)")
        }
        if listsImported > 0 || listsSkipped > 0 {
            parts.append("\(listsImported) list\(listsImported == 1 ? "" : "s") imported")
        }
        if listsSkipped > 0 {
            parts.append("\(listsSkipped) list\(listsSkipped == 1 ? "" : "s") skipped")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Service

final class BackupService {
    static let shared = BackupService()
    private init() {}

    // MARK: Private encoder / decoder

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Export

    /// Serialises the full collection to a `.backup` file in the system temp directory.
    ///
    /// The file contains only textual / numeric data; image URLs are stored as strings
    /// so the app can re-download artwork on demand without bloating the backup.
    ///
    /// - Returns: URL of the created backup file.
    func export(releases: [Release], lists: [RecordList]) throws -> URL {
        let backup = buildBackup(releases: releases, lists: lists)
        let data = try encoder.encode(backup)

        // Build filename: secondspin-app-data-2026-03-05T12-00-00Z.backup
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "secondspin-app-data-\(timestamp).backup"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    /// Reads a `.backup` file and upserts its data into the supplied SwiftData context.
    ///
    /// Matching strategy:
    /// - **Releases** are matched by `discogsId`. Already-present records are skipped.
    /// - **Lists** are matched by `id` (UUID). Already-present lists are skipped.
    ///
    /// The context is saved before the function returns.
    @discardableResult
    func importBackup(from url: URL, context: ModelContext) throws -> ImportResult {
        // Security-scoped access (required for files picked via UIDocumentPickerViewController)
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let backup = try decoder.decode(AppBackup.self, from: data)

        // ── Fetch existing IDs to detect duplicates ──────────────────────────
        let existingReleases = try context.fetch(FetchDescriptor<Release>())
        let existingReleaseIdSet = Set(existingReleases.map(\.discogsId))
        let existingListIdSet = Set(
            (try context.fetch(FetchDescriptor<RecordList>())).map(\.id)
        )

        // Pre-populate map so list→release relationships can reference already-stored releases
        var idToRelease: [Int: Release] = Dictionary(
            uniqueKeysWithValues: existingReleases.map { ($0.discogsId, $0) }
        )

        // ── Insert new releases ───────────────────────────────────────────────
        var releasesImported = 0
        var releasesSkipped = 0

        for dto in backup.releases {
            if existingReleaseIdSet.contains(dto.discogsId) {
                releasesSkipped += 1
                continue
            }

            let release = Release(
                discogsId: dto.discogsId,
                title: dto.title,
                artist: dto.artist,
                year: dto.year,
                label: dto.label,
                coverImageURL: dto.coverImageURL,
                thumbnailImageURL: dto.thumbnailImageURL,
                allImageURLs: dto.allImageURLs,
                genres: dto.genres,
                styles: dto.styles,
                format: dto.format,
                country: dto.country,
                barcode: dto.barcode,
                dateAdded: dto.dateAdded,
                tracklist: dto.tracklist.map {
                    Track(position: $0.position, title: $0.title, duration: $0.duration)
                }
            )
            context.insert(release)

            for copyDTO in dto.copies {
                let copy = Copy(
                    purchasePrice: copyDTO.purchasePrice,
                    condition: copyDTO.condition,
                    notes: copyDTO.notes,
                    dateAdded: copyDTO.dateAdded
                )
                copy.id = copyDTO.id
                copy.release = release
                context.insert(copy)
            }

            idToRelease[dto.discogsId] = release
            releasesImported += 1
        }

        // ── Insert new lists ──────────────────────────────────────────────────
        var listsImported = 0
        var listsSkipped = 0

        for dto in backup.lists {
            if existingListIdSet.contains(dto.id) {
                listsSkipped += 1
                continue
            }

            let list = RecordList(
                name: dto.name,
                listDescription: dto.listDescription,
                dateCreated: dto.dateCreated,
                orderIndex: dto.orderIndex
            )
            list.id = dto.id
            list.releases = dto.releaseDiscogsIds.compactMap { idToRelease[$0] }
            context.insert(list)
            listsImported += 1
        }

        try context.save()

        return ImportResult(
            releasesImported: releasesImported,
            releasesSkipped: releasesSkipped,
            listsImported: listsImported,
            listsSkipped: listsSkipped
        )
    }

    // MARK: - Private helpers

    private func buildBackup(releases: [Release], lists: [RecordList]) -> AppBackup {
        let releaseDTOs = releases.map { r in
            ReleaseBackupDTO(
                discogsId: r.discogsId,
                title: r.title,
                artist: r.artist,
                year: r.year,
                label: r.label,
                coverImageURL: r.coverImageURL,
                thumbnailImageURL: r.thumbnailImageURL,
                allImageURLs: r.allImageURLs,
                genres: r.genres,
                styles: r.styles,
                format: r.format,
                country: r.country,
                barcode: r.barcode,
                dateAdded: r.dateAdded,
                tracklist: r.tracklist.map {
                    TrackBackupDTO(position: $0.position, title: $0.title, duration: $0.duration)
                },
                copies: r.copies.map { c in
                    CopyBackupDTO(
                        id: c.id,
                        purchasePrice: c.purchasePrice,
                        condition: c.condition,
                        notes: c.notes,
                        dateAdded: c.dateAdded
                    )
                }
            )
        }

        let listDTOs = lists.map { l in
            ListBackupDTO(
                id: l.id,
                name: l.name,
                listDescription: l.listDescription,
                dateCreated: l.dateCreated,
                orderIndex: l.orderIndex,
                releaseDiscogsIds: l.releases.map(\.discogsId)
            )
        }

        return AppBackup(
            version: AppBackup.currentVersion,
            exportedAt: Date(),
            releases: releaseDTOs,
            lists: listDTOs
        )
    }
}
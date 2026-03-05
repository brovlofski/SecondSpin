//
//  SettingsView.swift
//  VinylVault
//
//  Settings screen with preferences
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

// MARK: - Share sheet (UIActivityViewController wrapper)

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Language enum

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var releases: [Release]
    @Query private var lists: [RecordList]

    @AppStorage("appearanceMode") private var appearanceMode = 0 // 0: System, 1: Light, 2: Dark
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage("appLanguage") private var appLanguageRaw = "en"

    // Cache size options in bytes
    private let cacheSizeOptions: [(label: String, bytes: Int)] = [
        ("256 MB", 256 * 1024 * 1024),
        ("512 MB", 512 * 1024 * 1024),
        ("1 GB",   1024 * 1024 * 1024),
        ("2 GB",   2 * 1024 * 1024 * 1024),
    ]

    // MARK: Cache state
    @State private var selectedCacheSizeIndex: Int = 2  // default 1 GB
    @State private var currentDiskCacheBytes: Int = 0
    @State private var showClearCacheConfirm = false

    // MARK: Misc state
    @State private var showingICloudComingSoon = false
    @State private var showingLanguageChangeAlert = false
    @State private var pendingLanguage: AppLanguage? = nil

    // MARK: Export state
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isExporting = false
    @State private var exportError: String? = nil
    @State private var showExportError = false

    // MARK: Import state
    @State private var showImportPicker = false
    @State private var isImporting = false
    @State private var importResult: ImportResult? = nil
    @State private var showImportResult = false
    @State private var importError: String? = nil
    @State private var showImportError = false

    // MARK: Sync state
    @State private var isSyncing = false
    @State private var syncProgress: Double = 0
    @State private var syncStatus: String = ""
    @State private var showSyncComplete = false
    @State private var syncResult: String = ""

    private var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: appLanguageRaw) ?? .english }
        set { appLanguageRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {

                // ── Appearance ────────────────────────────────────────────────
                Section {
                    Picker(NSLocalizedString("Appearance", comment: ""), selection: $appearanceMode) {
                        Text(NSLocalizedString("System", comment: "")).tag(0)
                        Text(NSLocalizedString("Light", comment: "")).tag(1)
                        Text(NSLocalizedString("Dark", comment: "")).tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label(NSLocalizedString("Appearance", comment: ""), systemImage: "paintbrush.fill")
                } footer: {
                    Text(NSLocalizedString("Choose how the app looks", comment: ""))
                }

                // ── iCloud Sync ───────────────────────────────────────────────
                Section {
                    // Sync Library button
                    Button {
                        syncLibrary()
                    } label: {
                        HStack {
                            if isSyncing {
                                ProgressView()
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Sync Library", comment: ""))
                                if isSyncing {
                                    Text(syncStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(
                                        String(
                                            format: NSLocalizedString("Update info for %d releases", comment: ""),
                                            releases.count
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .disabled(isSyncing || releases.isEmpty)
                    
                    if isSyncing {
                        ProgressView(value: syncProgress, total: 1.0)
                    }
                    
                    // iCloud Sync (coming soon)
                    HStack {
                        Image(systemName: "icloud.fill")
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("iCloud Sync", comment: ""))
                            Text(NSLocalizedString("Coming Soon", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            showingICloudComingSoon = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { showingICloudComingSoon = true }
                } header: {
                    Label(NSLocalizedString("Data Sync", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                } footer: {
                    Text(NSLocalizedString(
                        "Sync Library updates all releases with the latest data from Discogs (excluding images).",
                        comment: ""))
                }

                // ── Export / Import ───────────────────────────────────────────
                Section {
                    // Export
                    Button {
                        exportCollection()
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "arrow.up.doc.fill")
                                    .foregroundColor(.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Export Collection", comment: ""))
                                Text(
                                    String(
                                        format: NSLocalizedString("%d releases · %d lists", comment: ""),
                                        releases.count,
                                        lists.count
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isExporting || releases.isEmpty)

                    // Import
                    Button {
                        showImportPicker = true
                    } label: {
                        HStack {
                            if isImporting {
                                ProgressView()
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "arrow.down.doc.fill")
                                    .foregroundColor(.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Import from Backup", comment: ""))
                                Text(NSLocalizedString("Restores releases and lists from a .backup file", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(isImporting)
                } header: {
                    Label(NSLocalizedString("Export & Import", comment: ""), systemImage: "externaldrive.fill")
                } footer: {
                    Text(NSLocalizedString(
                        "Backups contain all textual data (tracklists, notes, prices). Images are not stored — they will be re-downloaded automatically.",
                        comment: ""))
                }

                // ── Language ──────────────────────────────────────────────────
                Section {
                    Picker(NSLocalizedString("Language", comment: ""), selection: Binding(
                        get: { appLanguage },
                        set: { newLanguage in
                            if newLanguage.rawValue != appLanguageRaw {
                                pendingLanguage = newLanguage
                                showingLanguageChangeAlert = true
                            }
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } header: {
                    Label(NSLocalizedString("Language", comment: ""), systemImage: "globe")
                } footer: {
                    Text(NSLocalizedString("The app will restart to apply the new language.", comment: ""))
                }

                // ── Image Cache ───────────────────────────────────────────────
                Section {
                    Picker(NSLocalizedString("Max Cache Size", comment: ""), selection: $selectedCacheSizeIndex) {
                        ForEach(cacheSizeOptions.indices, id: \.self) { idx in
                            Text(cacheSizeOptions[idx].label).tag(idx)
                        }
                    }
                    .onChange(of: selectedCacheSizeIndex) { _, newIdx in
                        ImageCache.shared.maxDiskCacheBytes = cacheSizeOptions[newIdx].bytes
                    }

                    HStack {
                        Text(NSLocalizedString("Current Usage", comment: ""))
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(currentDiskCacheBytes), countStyle: .file))
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive) {
                        showClearCacheConfirm = true
                    } label: {
                        Label(NSLocalizedString("Clear Image Cache", comment: ""), systemImage: "trash")
                    }
                } header: {
                    Label(NSLocalizedString("Image Cache", comment: ""), systemImage: "photo.stack")
                } footer: {
                    Text(NSLocalizedString(
                        "Cached images are stored on disk for faster loading. Clearing the cache frees up storage.",
                        comment: ""))
                }

                // ── About ─────────────────────────────────────────────────────
                Section {
                    HStack {
                        Text(NSLocalizedString("Version", comment: ""))
                        Spacer()
                        Text("1.0.0").foregroundColor(.secondary)
                    }
                    HStack {
                        Text(NSLocalizedString("Build", comment: ""))
                        Spacer()
                        Text("2026.03.05").foregroundColor(.secondary)
                    }
                } header: {
                    Label(NSLocalizedString("About", comment: ""), systemImage: "info.circle")
                }
            }
            .navigationTitle(NSLocalizedString("Settings", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .onAppear { refreshCacheInfo() }

            // ── Alerts ────────────────────────────────────────────────────────
            .alert(NSLocalizedString("Clear Image Cache", comment: ""), isPresented: $showClearCacheConfirm) {
                Button(NSLocalizedString("Clear", comment: ""), role: .destructive) {
                    ImageCache.shared.clear()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refreshCacheInfo() }
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString(
                    "This will delete all cached images. They will be re-downloaded as needed.",
                    comment: ""))
            }
            .alert(NSLocalizedString("iCloud Sync", comment: ""), isPresented: $showingICloudComingSoon) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString(
                    "iCloud sync is coming in a future update. Your collection will be backed up and available across all your devices.",
                    comment: ""))
            }
            .alert(NSLocalizedString("Change Language", comment: ""), isPresented: $showingLanguageChangeAlert) {
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { pendingLanguage = nil }
                Button(NSLocalizedString("Restart App", comment: "")) {
                    if let lang = pendingLanguage { applyLanguageAndRestart(lang) }
                }
            } message: {
                if let lang = pendingLanguage {
                    Text(String(
                        format: NSLocalizedString("Switch to %@ and restart the app to apply the change?", comment: ""),
                        lang.displayName
                    ))
                }
            }
            .alert(NSLocalizedString("Export Failed", comment: ""), isPresented: $showExportError) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(exportError ?? NSLocalizedString("An unknown error occurred.", comment: ""))
            }
            .alert(NSLocalizedString("Import Complete", comment: ""), isPresented: $showImportResult) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(importResult?.summary ?? "")
            }
            .alert(NSLocalizedString("Import Failed", comment: ""), isPresented: $showImportError) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(importError ?? NSLocalizedString("An unknown error occurred.", comment: ""))
            }
            .alert(NSLocalizedString("Sync Complete", comment: ""), isPresented: $showSyncComplete) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(syncResult)
            }

            // ── Share sheet (export) ──────────────────────────────────────────
            .sheet(isPresented: $showShareSheet) {
                ActivityViewController(activityItems: shareItems)
            }

            // ── File picker (import) ──────────────────────────────────────────
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
        }
    }

    // MARK: - Export

    private func exportCollection() {
        isExporting = true
        Task.detached(priority: .userInitiated) {
            do {
                // Capture arrays on the main actor before handing off
                let url = try await MainActor.run {
                    try BackupService.shared.export(releases: releases, lists: lists)
                }
                await MainActor.run {
                    shareItems = [url]
                    isExporting = false
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                    showExportError = true
                }
            }
        }
    }

    // MARK: - Import

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
            showImportError = true

        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            Task.detached(priority: .userInitiated) {
                do {
                    let result = try await MainActor.run {
                        try BackupService.shared.importBackup(from: url, context: modelContext)
                    }
                    await MainActor.run {
                        importResult = result
                        isImporting = false
                        showImportResult = true
                    }
                } catch {
                    await MainActor.run {
                        importError = error.localizedDescription
                        isImporting = false
                        showImportError = true
                    }
                }
            }
        }
    }

    // MARK: - Cache helpers

    private func refreshCacheInfo() {
        let stored = ImageCache.shared.maxDiskCacheBytes
        selectedCacheSizeIndex = cacheSizeOptions.firstIndex(where: { $0.bytes == stored }) ?? 2
        Task.detached(priority: .utility) {
            let bytes = ImageCache.shared.currentDiskCacheSizeBytes()
            await MainActor.run { currentDiskCacheBytes = bytes }
        }
    }

    // MARK: - Language helpers

    private func applyLanguageAndRestart(_ language: AppLanguage) {
        appLanguageRaw = language.rawValue
        pendingLanguage = nil
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
    }

    // MARK: - Sync Library

    private func syncLibrary() {
        guard !releases.isEmpty else { return }
        
        isSyncing = true
        syncProgress = 0
        syncStatus = NSLocalizedString("Starting sync...", comment: "")
        
        Task.detached(priority: .userInitiated) {
            var updatedCount = 0
            var errorCount = 0
            
            // Capture releases array on main actor
            let releasesToSync = await MainActor.run { Array(releases) }
            let totalReleases = releasesToSync.count
            
            for (index, release) in releasesToSync.enumerated() {
                // Update progress
                await MainActor.run {
                    syncProgress = Double(index) / Double(totalReleases)
                    syncStatus = String(
                        format: NSLocalizedString("Syncing %d of %d...", comment: ""),
                        index + 1,
                        totalReleases
                    )
                }
                
                do {
                    // Fetch latest details from Discogs
                    let details = try await DiscogsService.shared.getReleaseDetails(releaseId: release.discogsId)
                    
                    // Update release with latest data (excluding images)
                    await MainActor.run {
                        let artist = details.artists.first?.name ?? "Unknown Artist"
                        
                        release.title = details.title
                        release.artist = artist
                        release.year = details.year ?? 0
                        release.label = details.labels.first?.name ?? "Unknown Label"
                        release.catalogNumber = details.labels.first?.catno
                        release.genres = details.genres ?? []
                        release.styles = details.styles ?? []
                        release.format = details.formats?.first?.name ?? "LP"
                        release.formatDescriptions = details.formats?.first?.descriptions ?? []
                        release.country = details.country
                        release.barcode = details.identifiers?.first(where: { $0.type == "Barcode" })?.value
                        release.tracklist = details.tracklist?.map {
                            Track(position: $0.position, title: $0.title, duration: $0.duration)
                        } ?? []
                        
                        updatedCount += 1
                    }
                    
                    // Small delay to respect API rate limits
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    
                } catch {
                    print("Failed to sync release \(release.discogsId): \(error)")
                    errorCount += 1
                }
            }
            
            // Save changes
            await MainActor.run {
                do {
                    try modelContext.save()
                } catch {
                    print("Failed to save sync changes: \(error)")
                }
                
                // Show completion
                syncProgress = 1.0
                isSyncing = false
                
                if errorCount == 0 {
                    syncResult = String(
                        format: NSLocalizedString("Successfully updated %d releases", comment: ""),
                        updatedCount
                    )
                } else {
                    syncResult = String(
                        format: NSLocalizedString("Updated %d releases. %d failed.", comment: ""),
                        updatedCount,
                        errorCount
                    )
                }
                
                showSyncComplete = true
            }
        }
    }
}

#Preview {
    SettingsView()
}
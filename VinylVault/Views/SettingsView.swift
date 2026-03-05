//
//  SettingsView.swift
//  VinylVault
//
//  Settings screen with preferences
//

import SwiftUI

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

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = 0 // 0: System, 1: Light, 2: Dark
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @AppStorage("appLanguage") private var appLanguageRaw = "en"

    // Cache size options in bytes
    private let cacheSizeOptions: [(label: String, bytes: Int)] = [
        ("256 MB", 256 * 1024 * 1024),
        ("512 MB", 512 * 1024 * 1024),
        ("1 GB",   1024 * 1024 * 1024),
        ("2 GB",   2 * 1024 * 1024 * 1024)
    ]

    @State private var selectedCacheSizeIndex: Int = 2  // default 1 GB
    @State private var currentDiskCacheBytes: Int = 0
    @State private var showClearCacheConfirm = false
    @State private var showingICloudComingSoon = false
    @State private var showingLanguageChangeAlert = false
    @State private var pendingLanguage: AppLanguage? = nil

    private var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: appLanguageRaw) ?? .english }
        set { appLanguageRaw = newValue.rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Appearance Section
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

                // iCloud Sync Section
                Section {
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
                        // Info button instead of a functional toggle
                        Button {
                            showingICloudComingSoon = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingICloudComingSoon = true
                    }
                } header: {
                    Label(NSLocalizedString("Data Sync", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                } footer: {
                    Text(NSLocalizedString("iCloud sync will allow you to access your collection on all your devices. This feature is coming in a future update.", comment: ""))
                }

                // Language Section
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

                // Image Cache Section
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
                    Text(NSLocalizedString("Cached images are stored on disk for faster loading. Clearing the cache frees up storage.", comment: ""))
                }

                // About Section
                Section {
                    HStack {
                        Text(NSLocalizedString("Version", comment: ""))
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text(NSLocalizedString("Build", comment: ""))
                        Spacer()
                        Text("2026.03.05")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label(NSLocalizedString("About", comment: ""), systemImage: "info.circle")
                }
            }
            .navigationTitle(NSLocalizedString("Settings", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                refreshCacheInfo()
            }
            .alert(NSLocalizedString("Clear Image Cache", comment: ""), isPresented: $showClearCacheConfirm) {
                Button(NSLocalizedString("Clear", comment: ""), role: .destructive) {
                    ImageCache.shared.clear()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        refreshCacheInfo()
                    }
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("This will delete all cached images. They will be re-downloaded as needed.", comment: ""))
            }
            .alert(NSLocalizedString("iCloud Sync", comment: ""), isPresented: $showingICloudComingSoon) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("iCloud sync is coming in a future update. Your collection will be backed up and available across all your devices.", comment: ""))
            }
            .alert(NSLocalizedString("Change Language", comment: ""), isPresented: $showingLanguageChangeAlert) {
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                    pendingLanguage = nil
                }
                Button(NSLocalizedString("Restart App", comment: "")) {
                    if let lang = pendingLanguage {
                        applyLanguageAndRestart(lang)
                    }
                }
            } message: {
                if let lang = pendingLanguage {
                    Text(String(format: NSLocalizedString("Switch to %@ and restart the app to apply the change?", comment: ""), lang.displayName))
                }
            }
        }
    }

    // MARK: - Helpers

    private func refreshCacheInfo() {
        let stored = ImageCache.shared.maxDiskCacheBytes
        selectedCacheSizeIndex = cacheSizeOptions.firstIndex(where: { $0.bytes == stored }) ?? 2
        Task.detached(priority: .utility) {
            let bytes = ImageCache.shared.currentDiskCacheSizeBytes()
            await MainActor.run { currentDiskCacheBytes = bytes }
        }
    }

    private func applyLanguageAndRestart(_ language: AppLanguage) {
        appLanguageRaw = language.rawValue
        pendingLanguage = nil
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exit(0)
        }
    }
}

#Preview {
    SettingsView()
}
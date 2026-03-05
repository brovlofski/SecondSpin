//
//  SettingsView.swift
//  VinylVault
//
//  Settings screen with preferences
//

import SwiftUI
import CloudKit

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

    @State private var selectedCacheSizeIndex: Int = 2   // default 1 GB
    @State private var currentDiskCacheBytes: Int = 0
    @State private var showClearCacheConfirm = false

    @State private var showingCloudKitAlert = false
    @State private var cloudKitAlertMessage = ""
    @State private var isCheckingCloudKit = false
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
                    Toggle(isOn: $iCloudSyncEnabled) {
                        HStack {
                            Image(systemName: "icloud.fill")
                                .foregroundColor(.blue)
                            Text(NSLocalizedString("iCloud Sync", comment: ""))
                        }
                    }
                    .disabled(isCheckingCloudKit)
                    .onChange(of: iCloudSyncEnabled) { oldValue, newValue in
                        if newValue && !isCheckingCloudKit {
                            checkCloudKitStatus()
                        }
                    }
                    
                    if iCloudSyncEnabled {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(NSLocalizedString("Syncing with iCloud", comment: ""))
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label(NSLocalizedString("Data Sync", comment: ""), systemImage: "arrow.triangle.2.circlepath")
                } footer: {
                    Text(NSLocalizedString("Sync your collection, lists, and preferences across all your devices using iCloud", comment: ""))
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
            .alert(NSLocalizedString("iCloud Status", comment: ""), isPresented: $showingCloudKitAlert) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) { }
            } message: {
                Text(cloudKitAlertMessage)
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
    
    private func refreshCacheInfo() {
        // Load saved max size preference
        let stored = ImageCache.shared.maxDiskCacheBytes
        selectedCacheSizeIndex = cacheSizeOptions.firstIndex(where: { $0.bytes == stored }) ?? 2
        // Compute usage off main thread
        Task.detached(priority: .utility) {
            let bytes = ImageCache.shared.currentDiskCacheSizeBytes()
            await MainActor.run { currentDiskCacheBytes = bytes }
        }
    }

    private func applyLanguageAndRestart(_ language: AppLanguage) {
        // Save the new language preference
        appLanguageRaw = language.rawValue
        pendingLanguage = nil
        
        // Set the AppleLanguages key in UserDefaults so iOS uses it on next launch
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        // Give a brief moment for defaults to save, then exit
        // iOS will relaunch the app and pick up the new language
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exit(0)
        }
    }
    
    @MainActor
    private func checkCloudKitStatus() {
        guard !isCheckingCloudKit else { return }
        isCheckingCloudKit = true
        
        Task {
            do {
                let status = try await CKContainer.default().accountStatus()
                
                switch status {
                case .available:
                    cloudKitAlertMessage = NSLocalizedString("iCloud is available and ready to sync your data.", comment: "")
                    showingCloudKitAlert = true
                    isCheckingCloudKit = false
                case .noAccount:
                    cloudKitAlertMessage = NSLocalizedString("No iCloud account found. Please sign in to iCloud in Settings to enable sync.", comment: "")
                    iCloudSyncEnabled = false
                    showingCloudKitAlert = true
                    isCheckingCloudKit = false
                case .restricted:
                    cloudKitAlertMessage = NSLocalizedString("iCloud access is restricted on this device.", comment: "")
                    iCloudSyncEnabled = false
                    showingCloudKitAlert = true
                    isCheckingCloudKit = false
                case .couldNotDetermine:
                    cloudKitAlertMessage = NSLocalizedString("Could not determine iCloud status. Please check your connection.", comment: "")
                    iCloudSyncEnabled = false
                    showingCloudKitAlert = true
                    isCheckingCloudKit = false
                case .temporarilyUnavailable:
                    cloudKitAlertMessage = NSLocalizedString("iCloud is temporarily unavailable. Please try again later.", comment: "")
                    iCloudSyncEnabled = false
                    showingCloudKitAlert = true
                    isCheckingCloudKit = false
                @unknown default:
                    cloudKitAlertMessage = NSLocalizedString("Unknown iCloud status.", comment: "")
                    iCloudSyncEnabled = false
                    showingCloudKitAlert = true
                    isCheckingCloudKit = false
                }
            } catch {
                cloudKitAlertMessage = NSLocalizedString("Error checking iCloud status: \(error.localizedDescription)", comment: "")
                iCloudSyncEnabled = false
                showingCloudKitAlert = true
                isCheckingCloudKit = false
            }
        }
    }
}

#Preview {
    SettingsView()
}
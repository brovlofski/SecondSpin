//
//  VinylVaultApp.swift
//  VinylVault
//
//  Created by VinylVault Team
//

import SwiftUI
import SwiftData
import CarPlay

@main
struct VinylVaultApp: App {
    let modelContainer: ModelContainer
    @StateObject private var appState = AppState()
    @AppStorage("appearanceMode") private var appearanceMode = 0 // 0: System, 1: Light, 2: Dark

    init() {
        let schema = Schema([
            Release.self,
            Copy.self,
            RecordList.self
        ])

        if let container = VinylVaultApp.makeContainer(schema: schema) {
            modelContainer = container
            // Initialize system lists
            initializeSystemLists(in: container.mainContext)
        } else {
            fatalError("Could not initialize ModelContainer even after store reset.")
        }
    }

    // MARK: - Container factory

    private static func makeContainer(schema: Schema) -> ModelContainer? {
        // First attempt – normal path (works for fresh installs & compatible schemas).
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("⚠️ ModelContainer init failed: \(error)\nWiping persistent store and retrying…")
        }

        // Wipe the store, then try again.
        wipeStore()

        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            print("✅ ModelContainer recreated successfully after store wipe.")
            return container
        } catch {
            print("❌ ModelContainer init still failed after store wipe: \(error)")
            return nil
        }
    }

    // MARK: - Store wipe

    /// Recursively deletes every file that looks like a SwiftData / SQLite
    /// persistent store under the app's Application Support directory.
    /// SwiftData uses "default.store" / "default.store-wal" / "default.store-shm"
    /// by default, but some setups produce ".sqlite" variants.
    private static func wipeStore() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        deleteStoreFiles(in: appSupport, fm: fm)
    }

    private static func deleteStoreFiles(in directory: URL, fm: FileManager) {
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return }

        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                // Recurse into sub-directories (SwiftData may nest under bundle ID folder)
                deleteStoreFiles(in: item, fm: fm)
            } else {
                let name = item.lastPathComponent
                let ext  = item.pathExtension          // "store", "sqlite", …
                let storeExts  = ["store", "sqlite", "sqlite3"]
                let storeSuffixes = ["-wal", "-shm", "-wal2", "-journal"]
                if storeExts.contains(ext) || storeSuffixes.contains(where: { name.hasSuffix($0) }) {
                    do {
                        try fm.removeItem(at: item)
                        print("  🗑 Deleted: \(item.path)")
                    } catch {
                        print("  ⚠️ Could not delete \(item.lastPathComponent): \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .environmentObject(appState)
                .preferredColorScheme(colorScheme)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Maps the appearance mode setting to a SwiftUI ColorScheme
    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil  // System default
        }
    }
    
    // MARK: - System List Initialization
    
    /// Initializes system lists (Listen Later, etc.) if they don't exist
    private func initializeSystemLists(in context: ModelContext) {
        // Check if Listen Later list already exists
        let descriptor = FetchDescriptor<RecordList>(
            predicate: #Predicate { list in
                list.isSystemList == true && list.name == "Listen Later"
            }
        )
        
        do {
            let existingLists = try context.fetch(descriptor)
            if existingLists.isEmpty {
                // Create Listen Later system list
                let listenLaterList = RecordList.createSystemList(
                    type: .listenLater,
                    name: "Listen Later",
                    description: "Albums you want to listen to later"
                )
                context.insert(listenLaterList)
                try context.save()
                print("✅ Created 'Listen Later' system list")
            } else {
                print("✅ 'Listen Later' system list already exists")
            }
        } catch {
            print("❌ Error initializing system lists: \(error)")
        }
    }
}

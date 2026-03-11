//  ImageCache.swift
//  SecondSpin
//
//  Lightweight image caching layer with disk persistence and configurable max size
//

import SwiftUI

private let discogsToken = "ChNuGIHFtQvJKLkvcQQCEgcdDSVfXvKcVrxQASKO"

// MARK: - UserDefaults key for cache settings

private let kMaxCacheSizeKey = "imageCacheMaxBytes"
private let kDefaultMaxCacheBytes: Int = 1024 * 1024 * 1024 // 1 GB

// MARK: - ImageCache

/// Thread-safe image cache with in-memory NSCache and disk persistence.
/// Max disk size is read from UserDefaults so the Settings screen can adjust it.
final class ImageCache {
    static let shared = ImageCache()

    // In-memory cache (fast lookup, auto-evicted by OS under memory pressure)
    private let memoryCache = NSCache<NSString, UIImage>()

    // Disk cache directory
    private let diskCacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("ImageDiskCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // Serialise disk writes to avoid race conditions
    private let diskQueue = DispatchQueue(label: "com.secondspin.imagecache.disk", qos: .utility)

    private init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB in-memory cap
    }

    // MARK: - Max cache size (user-configurable)

    var maxDiskCacheBytes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: kMaxCacheSizeKey)
            return stored > 0 ? stored : kDefaultMaxCacheBytes
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kMaxCacheSizeKey)
        }
    }

    // MARK: - Public API

    func get(forKey key: String) -> UIImage? {
        // 1. Memory cache hit
        if let img = memoryCache.object(forKey: key as NSString) {
            return img
        }
        // 2. Disk cache hit – promote to memory
        if let img = readFromDisk(key: key) {
            memoryCache.setObject(img, forKey: key as NSString)
            return img
        }
        return nil
    }

    func set(_ image: UIImage, forKey key: String) {
        memoryCache.setObject(image, forKey: key as NSString)
        diskQueue.async { [weak self] in
            self?.writeToDisk(image, key: key)
            self?.evictOldFilesIfNeeded()
        }
    }

    func remove(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        diskQueue.async { [weak self] in
            guard let self else { return }
            let fileURL = self.diskFileURL(for: key)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func clear() {
        memoryCache.removeAllObjects()
        diskQueue.async { [weak self] in
            guard let self else { return }
            let files = (try? FileManager.default.contentsOfDirectory(
                at: self.diskCacheURL,
                includingPropertiesForKeys: nil
            )) ?? []
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    /// Returns the current total size of the disk cache in bytes (synchronous).
    func currentDiskCacheSizeBytes() -> Int {
        var total = 0
        let files = (try? FileManager.default.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        for f in files {
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += size
        }
        return total
    }

    // MARK: - Disk helpers

    private func diskFileURL(for key: String) -> URL {
        // Use a stable filename: hex-encoded UTF-8 bytes of the key
        let safe = key.data(using: .utf8)!
            .map { String(format: "%02x", $0) }
            .joined()
        // Limit filename length to avoid filesystem limits
        let truncated = String(safe.prefix(240))
        return diskCacheURL.appendingPathComponent(truncated + ".jpg")
    }

    private func readFromDisk(key: String) -> UIImage? {
        let url = diskFileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else { return nil }
        // Update modification date (used for LRU eviction)
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
        return img
    }

    private func writeToDisk(_ image: UIImage, key: String) {
        let url = diskFileURL(for: key)
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Remove oldest files (LRU by modification date) until total size is under the limit.
    private func evictOldFilesIfNeeded() {
        let limit = maxDiskCacheBytes
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: keys
        ) else { return }

        // Build sorted list (oldest first)
        var entries: [(url: URL, size: Int, date: Date)] = files.compactMap { url in
            guard let vals = try? url.resourceValues(forKeys: Set(keys)),
                  let size = vals.fileSize,
                  let date = vals.contentModificationDate else { return nil }
            return (url, size, date)
        }
        entries.sort { $0.date < $1.date }

        var total = entries.reduce(0) { $0 + $1.size }
        for entry in entries {
            guard total > limit else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

// MARK: - CachedAsyncImage

/// AsyncImage replacement with memory + disk caching and Discogs auth support.
public struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        guard let url = url, !url.absoluteString.isEmpty else {
            image = nil
            return
        }

        let cacheKey = url.absoluteString

        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            self.image = cached
            return
        }

        let host = url.host ?? ""
        let isDiscogs = host.contains("discogs.com")

        var effectiveURL = url
        if isDiscogs {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var items = components?.queryItems ?? []
            if !items.contains(where: { $0.name == "token" }) {
                items.append(URLQueryItem(name: "token", value: discogsToken))
                components?.queryItems = items
            }
            effectiveURL = components?.url ?? url
        }

        var request = URLRequest(
            url: effectiveURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        if isDiscogs {
            request.setValue("Discogs token=\(discogsToken)", forHTTPHeaderField: "Authorization")
            request.setValue("SecondSpin/1.0 +https://github.com/secondspin", forHTTPHeaderField: "User-Agent")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let loadedImage = UIImage(data: data) {
                ImageCache.shared.set(loadedImage, forKey: cacheKey)
                self.image = loadedImage
            }
        } catch {
            // Silently fail — placeholder stays visible
        }
    }
}
//
//  CarPlaySceneDelegate.swift
//  VinylVault
//
//  CarPlay UI – CPNowPlayingTemplate
//
//  ┌──────────────────────────────────────────────────────────────────┐
//  │                              │                                   │
//  │   ALBUM ART  (~60 %)         │   Title  (large)                  │
//  │                              │   Artist (medium)                 │
//  │                              │   Year · Genre · Wikipedia intro  │
//  │                              │                                   │
//  ├──────────────────────────────┴───────────────────────────────────┤
//  │  ◀◀  (disabled)   ■   ▶▶   │  [Spotify]   [Apple Music]         │
//  └──────────────────────────────────────────────────────────────────┘
//
//  Navigation: swipe left / right on the artwork (triggers ◀◀ / ▶▶ commands).
//  No other buttons are shown.
//

import MediaPlayer
import SwiftData
import UIKit

#if canImport(CarPlay)
import CarPlay

@available(iOS 14.0, *)
class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {

    // MARK: - State

    private var interfaceController: CPInterfaceController?
    private var releases: [Release] = []
    private var currentIndex = 0
    private var modelContainer: ModelContainer?

    /// Wikipedia extract cache – keyed "title|artist"
    private var wikiCache: [String: String] = [:]
    /// Artwork cache – keyed by URL string
    private var artworkCache: [String: UIImage] = [:]

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        configureRemoteCommands()
        Task { @MainActor in
            await loadCollectionThenShow()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        removeRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Collection loading (SwiftData)

    @MainActor
    private func loadCollectionThenShow() async {
        do {
            let schema = Schema([Release.self, Copy.self, RecordList.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            modelContainer = container

            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Release>(
                sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
            )
            releases = (try? context.fetch(descriptor)) ?? []
        } catch {
            releases = []
        }

        guard !releases.isEmpty else {
            await showEmptyState()
            return
        }

        currentIndex = albumOfTheDayIndex()
        await pushNowPlayingTemplate()
        await refreshNowPlayingContent(for: currentIndex, animated: false)
    }

    /// Stable daily index – changes at midnight, consistent across relaunches.
    private func albumOfTheDayIndex() -> Int {
        guard !releases.isEmpty else { return 0 }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return day % releases.count
    }

    // MARK: - Remote Commands  (◀◀ / ▶▶ → swipe left / swipe right on artwork)

    private func configureRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()

        // Previous – swipe right on artwork
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.removeTarget(nil)
        cc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.stepAlbum(by: -1) }
            return .success
        }

        // Next – swipe left on artwork
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.removeTarget(nil)
        cc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.stepAlbum(by: +1) }
            return .success
        }

        // Disable all playback controls – this is a browse-only experience.
        [cc.playCommand,
         cc.pauseCommand,
         cc.stopCommand,
         cc.togglePlayPauseCommand,
         cc.seekForwardCommand,
         cc.seekBackwardCommand,
         cc.changePlaybackPositionCommand].forEach { $0.isEnabled = false }
    }

    private func removeRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.previousTrackCommand.removeTarget(nil)
        cc.nextTrackCommand.removeTarget(nil)
    }

    @MainActor
    private func stepAlbum(by delta: Int) async {
        guard !releases.isEmpty else { return }
        currentIndex = ((currentIndex + delta) % releases.count + releases.count) % releases.count
        await refreshNowPlayingContent(for: currentIndex, animated: true)
    }

    // MARK: - CPNowPlayingTemplate

    @MainActor
    private func pushNowPlayingTemplate() async {
        let template = CPNowPlayingTemplate.shared
        template.isAlbumArtistButtonEnabled = false
        template.isUpNextButtonEnabled      = false
        rebuildButtonRail()
        try? await interfaceController?.setRootTemplate(template, animated: false)
    }

    /// Button rail – only Spotify and Apple Music; nothing else.
    private func rebuildButtonRail() {
        let spotifyBtn = CPNowPlayingImageButton(
            image: symbolImage("music.note.list")
        ) { [weak self] _ in
            self?.openURL(self?.spotifyURL)
        }

        let appleMusicBtn = CPNowPlayingImageButton(
            image: symbolImage("applelogo")
        ) { [weak self] _ in
            self?.openURL(self?.appleMusicURL)
        }

        CPNowPlayingTemplate.shared.updateNowPlayingButtons([spotifyBtn, appleMusicBtn])
    }

    // MARK: - Now Playing content

    /// Writes a placeholder to MPNowPlayingInfoCenter immediately, then loads
    /// real artwork + Wikipedia in parallel and updates again.
    @MainActor
    private func refreshNowPlayingContent(for index: Int, animated: Bool) async {
        guard index < releases.count else { return }
        let release = releases[index]

        // Instant update with placeholder while real data loads.
        let placeholder = makeArtworkPlaceholder(for: release)
        pushNowPlayingInfo(release: release, artwork: placeholder, wiki: nil)

        async let artworkTask = loadArtwork(for: release)
        async let wikiTask    = loadWikipedia(for: release)
        let (image, wikiText) = await (artworkTask, wikiTask)

        // Guard against stale responses if the user swiped away.
        guard currentIndex == index else { return }

        pushNowPlayingInfo(release: release,
                           artwork: image ?? placeholder,
                           wiki: wikiText)
    }

    /// Builds the three-line right panel:
    ///   Line 1 (title)   → album title
    ///   Line 2 (artist)  → artist
    ///   Line 3 (album)   → "year  ·  genre  ·  first sentence of Wikipedia intro"
    private func pushNowPlayingInfo(release: Release,
                                    artwork: UIImage?,
                                    wiki: String?) {
        // ── Right-panel line 3 ────────────────────────────────────────────────
        var parts: [String] = []

        if release.year > 0 { parts.append("\(release.year)") }

        let genre = release.genres.first ?? release.styles.first ?? ""
        if !genre.isEmpty { parts.append(genre) }

        if let label = release.label.isEmpty ? nil : release.label {
            parts.append(label)
        }

        if let wikiText = wiki, !wikiText.isEmpty {
            // First meaningful sentence, capped at 180 chars.
            let sentence = wikiText
                .components(separatedBy: ". ")
                .first(where: { $0.count > 20 }) ?? wikiText
            let clipped = sentence.count > 180
                ? String(sentence.prefix(177)) + "…"
                : sentence
            parts.append(clipped)
        }

        let subtitle = parts.joined(separator: "  ·  ")

        // ── MPNowPlayingInfoCenter dictionary ────────────────────────────────
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:                    release.title,
            MPMediaItemPropertyArtist:                   release.artist,
            MPMediaItemPropertyAlbumTitle:               subtitle,
            MPNowPlayingInfoPropertyPlaybackRate:         0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime:  0.0,
            MPMediaItemPropertyPlaybackDuration:          0.0,
            MPNowPlayingInfoPropertyMediaType:
                MPNowPlayingInfoMediaType.none.rawValue,
        ]

        if let art = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: art.size
            ) { _ in art }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Artwork loading

    private func loadArtwork(for release: Release) async -> UIImage? {
        let urlStr = release.coverImageURL
        guard !urlStr.isEmpty else { return nil }
        if let cached = artworkCache[urlStr] { return cached }
        guard let url = URL(string: urlStr),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let img = UIImage(data: data) else { return nil }
        artworkCache[urlStr] = img
        return img
    }

    /// Generates a vinyl-label placeholder with title / artist text.
    private func makeArtworkPlaceholder(for release: Release) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            // Background
            UIColor.systemIndigo.withAlphaComponent(0.85).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Vinyl disc
            let m: CGFloat = size.width * 0.06
            let vinylRect  = CGRect(x: m, y: m,
                                    width: size.width - m * 2,
                                    height: size.height - m * 2)
            UIColor.black.withAlphaComponent(0.72).setFill()
            UIBezierPath(ovalIn: vinylRect).fill()

            // Centre label circle
            let d = size.width * 0.38
            let labelRect = CGRect(x: (size.width - d) / 2,
                                   y: (size.height - d) / 2,
                                   width: d, height: d)
            UIColor.systemIndigo.setFill()
            UIBezierPath(ovalIn: labelRect).fill()

            // Title / artist text
            let titleFont  = UIFont.boldSystemFont(ofSize: size.width * 0.055)
            let artistFont = UIFont.systemFont(ofSize: size.width * 0.042)
            let white      = UIColor.white

            let tAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont, .foregroundColor: white
            ]
            let aAttr: [NSAttributedString.Key: Any] = [
                .font: artistFont,
                .foregroundColor: white.withAlphaComponent(0.85)
            ]

            let tStr = release.title  as NSString
            let aStr = release.artist as NSString

            let tSz = tStr.size(withAttributes: tAttr)
            let aSz = aStr.size(withAttributes: aAttr)
            let cx  = size.width / 2
            let cy  = size.height / 2

            tStr.draw(at: CGPoint(x: cx - tSz.width / 2, y: cy - tSz.height - 4),
                      withAttributes: tAttr)
            aStr.draw(at: CGPoint(x: cx - aSz.width / 2, y: cy + 4),
                      withAttributes: aAttr)
        }
    }

    // MARK: - Wikipedia loading

    private func loadWikipedia(for release: Release) async -> String? {
        let key = "\(release.title.lowercased())|\(release.artist.lowercased())"
        if let cached = wikiCache[key] { return cached }
        let text = try? await WikipediaService.shared.fetchAlbumDescription(
            albumTitle: release.title,
            artist: release.artist,
            year: release.year > 0 ? release.year : nil
        )
        if let text { wikiCache[key] = text }
        return text
    }

    // MARK: - Streaming link helpers

    private var spotifyURL: URL? {
        guard currentIndex < releases.count else { return nil }
        let r = releases[currentIndex]
        if let raw = r.spotifyAlbumURL, !raw.isEmpty, let u = URL(string: raw) { return u }
        let q = "\(r.artist) \(r.title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "spotify:search:\(q)")
    }

    private var appleMusicURL: URL? {
        guard currentIndex < releases.count else { return nil }
        let r = releases[currentIndex]
        if let raw = r.appleMusicAlbumURL, !raw.isEmpty, let u = URL(string: raw) { return u }
        let q = "\(r.artist) \(r.title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://music.apple.com/us/search?term=\(q)")
    }

    private func openURL(_ url: URL?) {
        guard let url else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Empty state

    @MainActor
    private func showEmptyState() async {
        let items = [
            CPInformationItem(
                title: "Collection is empty",
                detail: "Open the SecondSpin app on your iPhone and add some vinyl records to get started."
            )
        ]
        let actions = [CPTextButton(title: "OK", textStyle: .cancel) { _ in }]
        let template = CPInformationTemplate(
            title: "SecondSpin",
            layout: .twoColumn,
            items: items,
            actions: actions
        )
        try? await interfaceController?.setRootTemplate(template, animated: false)
    }

    // MARK: - Helpers

    private func symbolImage(_ name: String) -> UIImage {
        let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        return UIImage(systemName: name, withConfiguration: cfg)
            ?? UIImage(systemName: "music.note")!
    }
}

#else

class CarPlaySceneDelegate: NSObject {}

#endif
//
//  CarPlaySceneDelegate.swift
//  VinylVault
//
//  CarPlay scene delegate – Album of the Day, powered by your real collection.
//
//  Layout (CPNowPlayingTemplate):
//    Left  ~3/5  – large album artwork  ·  ◀ / ▶ transport controls (prev/next album)
//                  Spotify + Apple Music streaming buttons in the button rail.
//    Right ~2/5  – metadata panel: title (large), artist (medium),
//                  year · Wikipedia intro (small, fed via MPNowPlayingInfoCenter).
//

import MediaPlayer
import SwiftData

#if canImport(CarPlay)
import CarPlay

@available(iOS 14.0, *)
class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {

    // MARK: - State

    private var interfaceController: CPInterfaceController?
    private var releases: [Release] = []
    private var currentIndex = 0
    private var modelContainer: ModelContainer?

    /// Cached Wikipedia extracts keyed by "title|artist".
    private var wikiCache: [String: String] = [:]
    /// Artwork cache keyed by URL string.
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

    // MARK: - SwiftData

    /// Creates a ModelContainer matching the main app's schema and fetches all releases.
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

        if releases.isEmpty {
            await showEmptyState()
            return
        }

        currentIndex = albumOfTheDayIndex()
        await pushNowPlayingTemplate()

        // Kick off artwork + Wikipedia loads for the initial album.
        await refreshNowPlayingContent(for: currentIndex, animated: false)
    }

    /// Deterministic daily index – changes at midnight, stable across app launches.
    private func albumOfTheDayIndex() -> Int {
        guard !releases.isEmpty else { return 0 }
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return dayOfYear % releases.count
    }

    // MARK: - MPRemoteCommandCenter  (drives the ◀ / ▶ transport buttons)

    private func configureRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()

        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.removeTarget(nil)
        cc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            DispatchQueue.main.async { self.showPrevious() }
            return .success
        }

        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.removeTarget(nil)
        cc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            DispatchQueue.main.async { self.showNext() }
            return .success
        }

        // Disable playback controls – this is a collection browser, not a player.
        [cc.playCommand, cc.pauseCommand, cc.stopCommand,
         cc.togglePlayPauseCommand, cc.seekForwardCommand,
         cc.seekBackwardCommand, cc.changePlaybackPositionCommand].forEach {
            $0.isEnabled = false
        }
    }

    private func removeRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.previousTrackCommand.removeTarget(nil)
        cc.nextTrackCommand.removeTarget(nil)
    }

    // MARK: - Now Playing Template

    @MainActor
    private func pushNowPlayingTemplate() async {
        let template = CPNowPlayingTemplate.shared
        template.isAlbumArtistButtonEnabled = false
        template.isUpNextButtonEnabled = false
        updateButtonRail()
        try? await interfaceController?.setRootTemplate(template, animated: false)
    }

    /// Rebuilds the streaming / info button rail.
    private func updateButtonRail() {
        guard !releases.isEmpty else { return }

        let spotifyBtn = CPNowPlayingImageButton(
            image: symbolImage("play.circle.fill")
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.openSpotify() }
        }

        let appleMusicBtn = CPNowPlayingImageButton(
            image: symbolImage("music.note.list")
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.openAppleMusic() }
        }

        let infoBtn = CPNowPlayingImageButton(
            image: symbolImage("info.circle")
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.showAlbumDetail() }
        }

        let browseBtn = CPNowPlayingImageButton(
            image: symbolImage("rectangle.stack")
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.showCollectionList() }
        }

        CPNowPlayingTemplate.shared.updateNowPlayingButtons(
            [spotifyBtn, appleMusicBtn, infoBtn, browseBtn]
        )
    }

    // MARK: - Now Playing content refresh

    /// Writes metadata to MPNowPlayingInfoCenter, then asynchronously fetches
    /// real artwork and Wikipedia text before updating again.
    @MainActor
    private func refreshNowPlayingContent(for index: Int, animated: Bool) async {
        guard index < releases.count else { return }
        let release = releases[index]

        // 1. Immediate update with placeholder artwork.
        let placeholder = makeArtworkPlaceholder(for: release)
        pushNowPlayingInfo(release: release,
                           artwork: placeholder,
                           description: nil)

        // 2. Fetch real artwork in parallel with Wikipedia.
        async let artworkTask  = loadArtwork(for: release)
        async let wikiTask     = loadWikipedia(for: release)

        let (image, wikiText) = await (artworkTask, wikiTask)

        // Guard: user may have navigated away while we were fetching.
        guard currentIndex == index else { return }

        pushNowPlayingInfo(release: release,
                           artwork: image ?? placeholder,
                           description: wikiText)
    }

    /// Assembles the MPNowPlayingInfoCenter dictionary and pushes it.
    private func pushNowPlayingInfo(release: Release,
                                    artwork: UIImage?,
                                    description: String?) {
        // Right panel lines:
        //   Large  → title
        //   Medium → artist
        //   Small  → year · first sentence of Wikipedia intro
        let yearTag = release.year > 0 ? "\(release.year)" : ""
        var smallLine = yearTag

        if let wiki = description, !wiki.isEmpty {
            let firstSentence = String(
                wiki.components(separatedBy: ". ")
                    .first(where: { $0.count > 20 }) ?? wiki
            )
            let truncated = firstSentence.count > 160
                ? String(firstSentence.prefix(157)) + "…"
                : firstSentence
            smallLine = yearTag.isEmpty
                ? truncated
                : "\(yearTag)  ·  \(truncated)"
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle:                   release.title,
            MPMediaItemPropertyArtist:                  release.artist,
            MPMediaItemPropertyAlbumTitle:              smallLine,
            MPNowPlayingInfoPropertyPlaybackRate:        0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPMediaItemPropertyPlaybackDuration:         0.0,
            MPNowPlayingInfoPropertyMediaType:
                MPNowPlayingInfoMediaType.none.rawValue,
        ]

        if let art = artwork {
            let size = art.size
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: size
            ) { _ in art }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Artwork loading

    /// Returns a real image from the URL (with in-memory cache), or nil on failure.
    private func loadArtwork(for release: Release) async -> UIImage? {
        let urlStr = release.coverImageURL
        guard !urlStr.isEmpty else { return nil }

        if let cached = artworkCache[urlStr] { return cached }

        guard let url = URL(string: urlStr),
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }

        artworkCache[urlStr] = image
        return image
    }

    /// Generates a vinyl-label placeholder with title / artist text baked in.
    private func makeArtworkPlaceholder(for release: Release) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Background
            UIColor.systemIndigo.withAlphaComponent(0.85).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Vinyl disc
            let margin: CGFloat = size.width * 0.06
            let vinylRect = CGRect(
                x: margin, y: margin,
                width: size.width  - margin * 2,
                height: size.height - margin * 2
            )
            UIColor.black.withAlphaComponent(0.72).setFill()
            UIBezierPath(ovalIn: vinylRect).fill()

            // Centre label circle
            let labelDiam = size.width * 0.38
            let labelRect = CGRect(
                x: (size.width  - labelDiam) / 2,
                y: (size.height - labelDiam) / 2,
                width: labelDiam, height: labelDiam
            )
            UIColor.systemIndigo.setFill()
            UIBezierPath(ovalIn: labelRect).fill()

            // Text on label
            let titleFont  = UIFont.boldSystemFont(ofSize: size.width * 0.055)
            let artistFont = UIFont.systemFont(ofSize: size.width * 0.042)
            let white      = UIColor.white

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont, .foregroundColor: white
            ]
            let artistAttr: [NSAttributedString.Key: Any] = [
                .font: artistFont,
                .foregroundColor: white.withAlphaComponent(0.85)
            ]

            let titleStr  = (release.title  as NSString)
            let artistStr = (release.artist as NSString)

            let tSize = titleStr.size(withAttributes: titleAttr)
            let aSize = artistStr.size(withAttributes: artistAttr)
            let cx = size.width / 2
            let cy = size.height / 2

            titleStr.draw(
                at: CGPoint(x: cx - tSize.width / 2, y: cy - tSize.height - 4),
                withAttributes: titleAttr
            )
            artistStr.draw(
                at: CGPoint(x: cx - aSize.width / 2, y: cy + 4),
                withAttributes: artistAttr
            )
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
        if let text {
            wikiCache[key] = text
        }
        return text
    }

    // MARK: - Navigation

    private func showPrevious() {
        guard !releases.isEmpty else { return }
        currentIndex = (currentIndex - 1 + releases.count) % releases.count
        Task { @MainActor in
            await refreshNowPlayingContent(for: currentIndex, animated: true)
        }
    }

    private func showNext() {
        guard !releases.isEmpty else { return }
        currentIndex = (currentIndex + 1) % releases.count
        Task { @MainActor in
            await refreshNowPlayingContent(for: currentIndex, animated: true)
        }
    }

    // MARK: - Collection list  (browse all releases)

    @MainActor
    private func showCollectionList() async {
        let sections: [CPListSection] = {
            var items = releases.enumerated().map { idx, r -> CPListItem in
                let subtitle = r.year > 0 ? "\(r.artist)  ·  \(r.year)" : r.artist
                let item = CPListItem(text: r.title, detailText: subtitle)
                item.handler = { [weak self] _, completion in
                    guard let self else { completion(); return }
                    self.currentIndex = idx
                    Task { @MainActor in
                        try? await self.interfaceController?.popTemplate(animated: true)
                        await self.refreshNowPlayingContent(for: idx, animated: true)
                    }
                    completion()
                }
                return item
            }
            return [CPListSection(items: items)]
        }()

        let listTemplate = CPListTemplate(
            title: "My Collection",
            sections: sections
        )
        listTemplate.emptyViewTitleVariants   = ["No Records"]
        listTemplate.emptyViewSubtitleVariants = ["Add records in the SecondSpin app."]

        try? await interfaceController?.pushTemplate(listTemplate, animated: true)
    }

    // MARK: - Album detail  (CPInformationTemplate)

    @MainActor
    private func showAlbumDetail() async {
        guard currentIndex < releases.count else { return }
        let release = releases[currentIndex]

        var items: [CPInformationItem] = []

        items.append(CPInformationItem(title: "Artist", detail: release.artist))

        if release.year > 0 {
            items.append(CPInformationItem(title: "Year", detail: "\(release.year)"))
        }
        if !release.label.isEmpty {
            items.append(CPInformationItem(title: "Label", detail: release.label))
        }
        if !release.genres.isEmpty {
            items.append(CPInformationItem(
                title: "Genre",
                detail: release.genres.joined(separator: ", ")
            ))
        }
        if !release.fullFormatDisplay.isEmpty {
            items.append(CPInformationItem(title: "Format", detail: release.fullFormatDisplay))
        }

        // Wikipedia snippet – use cache if already loaded.
        let wikiKey = "\(release.title.lowercased())|\(release.artist.lowercased())"
        if let wiki = wikiCache[wikiKey], !wiki.isEmpty {
            let sentences = wiki.components(separatedBy: ". ")
            let preview   = sentences.prefix(3).joined(separator: ". ")
            let clipped   = preview.count > 320
                ? String(preview.prefix(317)) + "…"
                : preview
            items.append(CPInformationItem(title: "About", detail: clipped))
        }

        // Copy condition summary
        let copies = release.copies
        if !copies.isEmpty {
            let conditions = copies.map { $0.condition }.filter { !$0.isEmpty }
            if !conditions.isEmpty {
                items.append(CPInformationItem(
                    title: copies.count == 1 ? "Condition" : "Conditions",
                    detail: conditions.joined(separator: "  ·  ")
                ))
            }
            let prices = copies.compactMap { c -> String? in
                guard let p = c.purchasePrice else { return nil }
                return String(format: "$%.2f", p)
            }
            if !prices.isEmpty {
                items.append(CPInformationItem(
                    title: copies.count == 1 ? "Paid" : "Prices",
                    detail: prices.joined(separator: "  ·  ")
                ))
            }
        }

        let actions: [CPTextButton] = [
            CPTextButton(title: "Spotify", textStyle: .confirm) { [weak self] _ in
                self?.openSpotify()
            },
            CPTextButton(title: "Apple Music", textStyle: .normal) { [weak self] _ in
                self?.openAppleMusic()
            },
            CPTextButton(title: "Back", textStyle: .cancel) { [weak self] _ in
                Task { [weak self] in try? await self?.interfaceController?.popTemplate(animated: true) }
            },
        ]

        let detailTemplate = CPInformationTemplate(
            title: release.title,
            layout: .twoColumn,
            items: items,
            actions: actions
        )

        try? await interfaceController?.pushTemplate(detailTemplate, animated: true)
    }

    // MARK: - Streaming

    private func openSpotify() {
        guard currentIndex < releases.count else { return }
        let release = releases[currentIndex]

        if let raw = release.spotifyAlbumURL, !raw.isEmpty, let url = URL(string: raw) {
            UIApplication.shared.open(url)
        } else {
            let q = "\(release.artist) \(release.title)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "spotify:search:\(q)") {
                UIApplication.shared.open(url)
            }
        }
    }

    private func openAppleMusic() {
        guard currentIndex < releases.count else { return }
        let release = releases[currentIndex]

        if let raw = release.appleMusicAlbumURL, !raw.isEmpty, let url = URL(string: raw) {
            UIApplication.shared.open(url)
        } else {
            let q = "\(release.artist) \(release.title)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://music.apple.com/us/search?term=\(q)") {
                UIApplication.shared.open(url)
            }
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
        let actions = [
            CPTextButton(title: "OK", textStyle: .cancel) { _ in }
        ]
        let emptyTemplate = CPInformationTemplate(
            title: "SecondSpin",
            layout: .twoColumn,
            items: items,
            actions: actions
        )
        try? await interfaceController?.setRootTemplate(emptyTemplate, animated: false)
    }

    // MARK: - Helpers

    private func symbolImage(_ name: String) -> UIImage {
        let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        return UIImage(systemName: name, withConfiguration: cfg)
            ?? UIImage(systemName: "music.note")!
    }
}

#else

// Fallback for non-CarPlay builds
class CarPlaySceneDelegate: NSObject {}

#endif
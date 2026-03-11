//
//  CarPlaySceneDelegate.swift
//  VinylVault
//
//  CarPlay UI – CPNowPlayingTemplate
//
//  Shows full-screen album artwork for the current "Album of the Day".
//  Swipe left / right on the artwork to browse the collection.
//  Two buttons in the rail: Spotify and Apple Music (same asset-catalog
//  icons as the Home screen).
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
        await refreshArtwork(for: currentIndex)
    }

    /// Stable daily index – changes at midnight, consistent across relaunches.
    private func albumOfTheDayIndex() -> Int {
        guard !releases.isEmpty else { return 0 }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return day % releases.count
    }

    // MARK: - Remote Commands (swipe left / right on artwork)

    private func configureRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()

        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.removeTarget(nil)
        cc.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.stepAlbum(by: -1) }
            return .success
        }

        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.removeTarget(nil)
        cc.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in await self.stepAlbum(by: +1) }
            return .success
        }

        // Keep playback controls disabled – browse-only experience.
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
        await refreshArtwork(for: currentIndex)
    }

    // MARK: - CPNowPlayingTemplate

    @MainActor
    private func pushNowPlayingTemplate() async {
        let template = CPNowPlayingTemplate.shared
        template.isAlbumArtistButtonEnabled = false
        template.isUpNextButtonEnabled = false
        buildButtonRail()
        guard let interfaceController else { return }
        do {
            try await interfaceController.setRootTemplate(template, animated: false)
        } catch {
            print("Failed to set Now Playing template: \(error)")
        }
    }

    /// Two buttons only: Spotify (left) and Apple Music (right).
    /// Uses the same named assets as the Home screen ("SpotifyIcon", "AppleMusicIcon").
    private func buildButtonRail() {
        let spotifyImage = UIImage(named: "SpotifyIcon")
            ?? UIImage(systemName: "music.note.list")!

        let appleMusicImage = UIImage(named: "AppleMusicIcon")
            ?? UIImage(systemName: "music.note")!

        let spotifyBtn = CPNowPlayingImageButton(image: spotifyImage) { [weak self] _ in
            self?.openURL(self?.streamingURL(\.spotifyAlbumURL,
                                             fallback: "spotify:search:"))
        }

        let appleMusicBtn = CPNowPlayingImageButton(image: appleMusicImage) { [weak self] _ in
            self?.openURL(self?.streamingURL(\.appleMusicAlbumURL,
                                             fallback: "https://music.apple.com/us/search?term="))
        }

        CPNowPlayingTemplate.shared.updateNowPlayingButtons([spotifyBtn, appleMusicBtn])
    }

    // MARK: - Artwork refresh

    /// Writes placeholder instantly, then loads real artwork and updates.
    @MainActor
    private func refreshArtwork(for index: Int) async {
        guard index < releases.count else { return }
        let release = releases[index]

        // Show placeholder immediately so CarPlay renders the artwork area.
        let placeholder = makeVinylPlaceholder(for: release)
        publishToNowPlayingCenter(release: release, image: placeholder)

        // Load real artwork in background.
        let realImage = await loadArtwork(for: release)

        // Guard against stale response if user swiped again.
        guard currentIndex == index else { return }

        publishToNowPlayingCenter(release: release, image: realImage ?? placeholder)
    }

    /// Pushes the minimum required info to `MPNowPlayingInfoCenter`.
    ///
    /// Setting `MPNowPlayingInfoPropertyMediaType = .music` is **required** for
    /// CarPlay's `CPNowPlayingTemplate` to render the artwork panel.
    private func publishToNowPlayingCenter(release: Release, image: UIImage) {
        let artworkSize = CGSize(width: 600, height: 600)
        let artwork = MPMediaItemArtwork(boundsSize: artworkSize) { requestedSize in
            // Resize image to whatever CarPlay asks for.
            UIGraphicsImageRenderer(size: requestedSize).image { _ in
                image.draw(in: CGRect(origin: .zero, size: requestedSize))
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle:                   release.title,
            MPMediaItemPropertyArtist:                  release.artist,
            MPMediaItemPropertyArtwork:                 artwork,
            // .audio tells CarPlay to render the full artwork layout.
            MPNowPlayingInfoPropertyMediaType:          MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate:       0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPMediaItemPropertyPlaybackDuration:        0.0,
        ]
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

    /// Vinyl-disc placeholder rendered entirely in Core Graphics.
    private func makeVinylPlaceholder(for release: Release) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            // Background
            UIColor.systemIndigo.withAlphaComponent(0.85).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Vinyl disc
            let m: CGFloat = size.width * 0.06
            let vinylRect = CGRect(x: m, y: m,
                                   width: size.width - m * 2,
                                   height: size.height - m * 2)
            UIColor.black.withAlphaComponent(0.72).setFill()
            UIBezierPath(ovalIn: vinylRect).fill()

            // Grooves (thin concentric circles)
            let cx = size.width / 2, cy = size.height / 2
            UIColor.white.withAlphaComponent(0.06).setStroke()
            for r in stride(from: size.width * 0.20, through: size.width * 0.45, by: size.width * 0.025) {
                let path = UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r,
                                                       width: r * 2, height: r * 2))
                path.lineWidth = 0.5
                path.stroke()
            }

            // Centre label circle
            let d = size.width * 0.36
            let labelRect = CGRect(x: (size.width - d) / 2,
                                   y: (size.height - d) / 2,
                                   width: d, height: d)
            UIColor.systemIndigo.setFill()
            UIBezierPath(ovalIn: labelRect).fill()

            // Centre hole
            let hole: CGFloat = size.width * 0.04
            UIColor.black.withAlphaComponent(0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: cx - hole / 2, y: cy - hole / 2,
                                        width: hole, height: hole)).fill()

            // Title + artist text on the label
            let titleFont  = UIFont.boldSystemFont(ofSize: size.width * 0.055)
            let artistFont = UIFont.systemFont(ofSize: size.width * 0.040)
            let white = UIColor.white

            let tAttr: [NSAttributedString.Key: Any] = [.font: titleFont,  .foregroundColor: white]
            let aAttr: [NSAttributedString.Key: Any] = [.font: artistFont,
                                                         .foregroundColor: white.withAlphaComponent(0.82)]

            let tStr = release.title  as NSString
            let aStr = release.artist as NSString

            let tSz = tStr.size(withAttributes: tAttr)
            let aSz = aStr.size(withAttributes: aAttr)

            tStr.draw(at: CGPoint(x: cx - tSz.width / 2, y: cy - tSz.height - 4), withAttributes: tAttr)
            aStr.draw(at: CGPoint(x: cx - aSz.width / 2, y: cy + 4), withAttributes: aAttr)
        }
    }

    // MARK: - Streaming URLs

    private func streamingURL(_ keyPath: KeyPath<Release, String?>,
                               fallback prefix: String) -> URL? {
        guard currentIndex < releases.count else { return nil }
        let r = releases[currentIndex]
        if let stored = r[keyPath: keyPath], !stored.isEmpty, let u = URL(string: stored) {
            return u
        }
        let q = "\(r.artist) \(r.title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "\(prefix)\(q)")
    }

    private func openURL(_ url: URL?) {
        guard let url else { return }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }

    // MARK: - Empty state

    @MainActor
    private func showEmptyState() async {
        let items = [
            CPInformationItem(
                title: "Collection is empty",
                detail: "Open SecondSpin on your iPhone and add some vinyl records to get started."
            )
        ]
        let actions = [CPTextButton(title: "OK", textStyle: .cancel) { _ in }]
        let template = CPInformationTemplate(
            title: "SecondSpin",
            layout: .twoColumn,
            items: items,
            actions: actions
        )
        guard let interfaceController else { return }
        do {
            try await interfaceController.setRootTemplate(template, animated: false)
        } catch {
            print("Failed to set empty state template: \(error)")
        }
    }
}

#else

class CarPlaySceneDelegate: NSObject {}

#endif

//
//  CarPlaySceneDelegate.swift
//  VinylVault
//
//  CarPlay scene delegate for SecondSpin – Album of the Day.
//
//  Layout (via CPNowPlayingTemplate):
//    Left ~3/5  – large album artwork; ◀ / ▶ transport controls on either side;
//                 streaming buttons (Spotify, Apple Music) along the bottom rail.
//    Right ~2/5 – metadata panel: album title, artist, description text
//                 (fed through MPNowPlayingInfoCenter).
//

import SwiftUI
import MediaPlayer

#if canImport(CarPlay)
import CarPlay

@available(iOS 14.0, *)
class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {

    // MARK: - Types

    struct AlbumEntry {
        let title: String
        let artist: String
        let year: Int
        let description: String
        let spotifyURL: String?
        let appleMusicURL: String?
    }

    // MARK: - State

    private var interfaceController: CPInterfaceController?
    private var currentIndex = 0

    private let albums: [AlbumEntry] = [
        AlbumEntry(
            title: "Abbey Road",
            artist: "The Beatles",
            year: 1969,
            description: "The eleventh studio album by the Beatles — the last recorded together. Side two's medley of fragments became one of rock's most celebrated sequences.",
            spotifyURL: "spotify:album:0ETFjACtuP2ADo6LFhL6HN",
            appleMusicURL: "https://music.apple.com/us/album/abbey-road/1441133100"
        ),
        AlbumEntry(
            title: "Kind of Blue",
            artist: "Miles Davis",
            year: 1959,
            description: "Widely regarded as the greatest jazz album ever recorded. Davis abandoned bebop's complex changes for modal improvisation, giving each soloist vast harmonic space.",
            spotifyURL: "spotify:album:1weenld61qoidwYuZ1GESA",
            appleMusicURL: "https://music.apple.com/us/album/kind-of-blue/1440650935"
        ),
        AlbumEntry(
            title: "The Dark Side of the Moon",
            artist: "Pink Floyd",
            year: 1973,
            description: "Pink Floyd's eighth studio album spent over 900 weeks on the Billboard 200. Themes of time, greed, and mental illness are woven through an unbroken conceptual arc.",
            spotifyURL: "spotify:album:4LH4d3cOWNNsVw41Gqt2kv",
            appleMusicURL: "https://music.apple.com/us/album/the-dark-side-of-the-moon/1065977164"
        ),
        AlbumEntry(
            title: "Blue",
            artist: "Joni Mitchell",
            year: 1971,
            description: "Ranked the greatest album of all time by Rolling Stone in 2020. Mitchell's confessional songwriting and open guitar tunings redefined the singer-songwriter form.",
            spotifyURL: "spotify:album:1vz94WpXDVYIEGja8cjFNa",
            appleMusicURL: "https://music.apple.com/us/album/blue/1440742903"
        ),
        AlbumEntry(
            title: "Rumours",
            artist: "Fleetwood Mac",
            year: 1977,
            description: "Recorded during the simultaneous breakdown of two relationships within the band. The result became one of the best-selling albums in history with four Top 10 singles.",
            spotifyURL: "spotify:album:1bt6q2SruS5GXDXFbHM4MY",
            appleMusicURL: "https://music.apple.com/us/album/rumours/1440839912"
        )
    ]

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        configureRemoteCommands()
        pushNowPlayingTemplate()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        removeRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - MPRemoteCommandCenter (drives the ◀ / ▶ transport buttons)

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

        // Disable controls that don't apply
        cc.playCommand.isEnabled = false
        cc.pauseCommand.isEnabled = false
        cc.stopCommand.isEnabled = false
        cc.togglePlayPauseCommand.isEnabled = false
        cc.seekForwardCommand.isEnabled = false
        cc.seekBackwardCommand.isEnabled = false
        cc.changePlaybackPositionCommand.isEnabled = false
    }

    private func removeRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.previousTrackCommand.removeTarget(nil)
        cc.nextTrackCommand.removeTarget(nil)
    }

    // MARK: - Template setup

    private func pushNowPlayingTemplate() {
        refreshNowPlayingInfo()

        let template = CPNowPlayingTemplate.shared

        // Right panel: show album title + artist as tappable info button
        template.isAlbumArtistButtonEnabled = true

        // Bottom streaming buttons  (max 5 custom buttons in the button rail)
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
        template.updateNowPlayingButtons([spotifyBtn, appleMusicBtn])

        interfaceController?.setRootTemplate(template, animated: true)
    }

    // MARK: - Now Playing Info  (populates the right-panel metadata area)

    private func refreshNowPlayingInfo() {
        let album = albums[currentIndex]

        // The metadata block that CarPlay's right panel renders:
        //   Large line  → MPMediaItemPropertyTitle       (album name)
        //   Medium line → MPMediaItemPropertyArtist      (artist)
        //   Small line  → MPMediaItemPropertyAlbumTitle  (year • description)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:       album.title,
            MPMediaItemPropertyArtist:      album.artist,
            MPMediaItemPropertyAlbumTitle:  "\(album.year)  ·  \(album.description)",
            MPNowPlayingInfoPropertyPlaybackRate:       0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPMediaItemPropertyPlaybackDuration:        0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.none.rawValue
        ]

        // Album artwork – use a bold vinyl-record SF Symbol as placeholder.
        // When the app is wired to Core Data / Discogs images, swap in the real UIImage here.
        let artworkSize = CGSize(width: 600, height: 600)
        let artworkImage = makeArtworkPlaceholder(size: artworkSize, album: album)
        info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
            boundsSize: artworkSize
        ) { _ in artworkImage }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Keep the "Up Next" title in sync (shown beneath the transport buttons)
        CPNowPlayingTemplate.shared.isUpNextButtonEnabled = false
    }

    // MARK: - Navigation

    private func showNext() {
        currentIndex = (currentIndex + 1) % albums.count
        refreshNowPlayingInfo()
    }

    private func showPrevious() {
        currentIndex = (currentIndex - 1 + albums.count) % albums.count
        refreshNowPlayingInfo()
    }

    // MARK: - Streaming

    private func openSpotify() {
        let album = albums[currentIndex]
        if let raw = album.spotifyURL, let url = URL(string: raw) {
            UIApplication.shared.open(url)
        } else {
            let q = "\(album.artist) \(album.title)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "spotify:search:\(q)") {
                UIApplication.shared.open(url)
            }
        }
    }

    private func openAppleMusic() {
        let album = albums[currentIndex]
        if let raw = album.appleMusicURL, let url = URL(string: raw) {
            UIApplication.shared.open(url)
        } else {
            let q = "\(album.artist) \(album.title)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://music.apple.com/us/search?term=\(q)") {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Helpers

    private func symbolImage(_ name: String) -> UIImage {
        let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        return UIImage(systemName: name, withConfiguration: cfg)
            ?? UIImage(systemName: "music.note")!
    }

    /// Renders a simple vinyl-record placeholder that fills the artwork area.
    private func makeArtworkPlaceholder(size: CGSize, album: AlbumEntry) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Dark background
            UIColor.systemIndigo.withAlphaComponent(0.85).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Vinyl circle
            let margin: CGFloat = size.width * 0.06
            let vinylRect = CGRect(
                x: margin, y: margin,
                width: size.width - margin * 2,
                height: size.height - margin * 2
            )
            UIColor.black.withAlphaComponent(0.7).setFill()
            UIBezierPath(ovalIn: vinylRect).fill()

            // Label circle
            let labelSize = size.width * 0.38
            let labelRect = CGRect(
                x: (size.width - labelSize) / 2,
                y: (size.height - labelSize) / 2,
                width: labelSize,
                height: labelSize
            )
            UIColor.systemIndigo.setFill()
            UIBezierPath(ovalIn: labelRect).fill()

            // Album title on label
            let titleFont = UIFont.boldSystemFont(ofSize: size.width * 0.055)
            let artistFont = UIFont.systemFont(ofSize: size.width * 0.042)
            let textColor = UIColor.white

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: textColor
            ]
            let artistAttr: [NSAttributedString.Key: Any] = [
                .font: artistFont,
                .foregroundColor: textColor.withAlphaComponent(0.85)
            ]

            let titleStr = album.title as NSString
            let artistStr = album.artist as NSString

            let titleSize = titleStr.size(withAttributes: titleAttr)
            let artistSize = artistStr.size(withAttributes: artistAttr)

            let centerX = size.width / 2
            let centerY = size.height / 2

            titleStr.draw(
                at: CGPoint(x: centerX - titleSize.width / 2, y: centerY - titleSize.height - 4),
                withAttributes: titleAttr
            )
            artistStr.draw(
                at: CGPoint(x: centerX - artistSize.width / 2, y: centerY + 4),
                withAttributes: artistAttr
            )
        }
    }
}

#else

// Fallback for non-CarPlay builds
class CarPlaySceneDelegate: NSObject {}

#endif
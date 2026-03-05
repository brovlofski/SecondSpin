//
//  StreamingLinkService.swift
//  VinylVault
//
//  Service for generating streaming platform links
//

import Foundation
import UIKit

class StreamingLinkService {
    static let shared = StreamingLinkService()

    private init() {}

    // MARK: - Spotify

    /// Returns the Spotify app deep-link URL (`spotify:search:<query>`).
    func spotifyAppURL(artist: String, album: String) -> URL? {
        let query = "\(artist) \(album)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "spotify:search:\(query)")
    }

    /// Returns the Spotify web search URL (fallback when the app is not installed).
    func spotifyWebURL(artist: String, album: String) -> URL? {
        let query = "\(artist) \(album)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://open.spotify.com/search/\(query)")
    }

    // MARK: - Apple Music

    /// Returns the Apple Music universal link for search.
    /// iOS intercepts `https://music.apple.com/…` and opens the Music app when installed.
    func appleMusicURL(artist: String, album: String) -> URL? {
        let query = "\(artist) \(album)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://music.apple.com/search?term=\(query)")
    }

    // MARK: - Open helpers

    /// Opens the Spotify iOS app; falls back to the web URL if Spotify is not installed.
    func openSpotify(artist: String, album: String) {
        if let appURL = spotifyAppURL(artist: artist, album: album),
           UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = spotifyWebURL(artist: artist, album: album) {
            UIApplication.shared.open(webURL)
        }
    }

    /// Opens the Apple Music iOS app via its universal link (also works as a web fallback).
    func openAppleMusic(artist: String, album: String) {
        if let url = appleMusicURL(artist: artist, album: album) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Legacy helpers (kept for backward compatibility)

    func generateSpotifyLink(artist: String, album: String) -> URL? {
        spotifyWebURL(artist: artist, album: album)
    }

    func generateAppleMusicLink(artist: String, album: String) -> URL? {
        appleMusicURL(artist: artist, album: album)
    }
}
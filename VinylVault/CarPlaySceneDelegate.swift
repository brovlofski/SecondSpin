//
//  CarPlaySceneDelegate.swift
//  VinylVault
//
//  CarPlay scene delegate for SecondSpin CarPlay integration.
//

import SwiftUI

#if canImport(CarPlay)
import CarPlay

@available(iOS 14.0, *)
class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {
    
    private var interfaceController: CPInterfaceController?
    private var currentAlbumIndex = 0
    private var albums: [AlbumOfTheDay] = []
    
    // Sample data for testing
    struct AlbumOfTheDay {
        let title: String
        let artist: String
        let year: Int
        let coverImageURL: String?
        let description: String
        let spotifyURL: String?
        let appleMusicURL: String?
    }
    
    override init() {
        super.init()
        loadSampleAlbums()
    }
    
    private func loadSampleAlbums() {
        albums = [
            AlbumOfTheDay(
                title: "Abbey Road",
                artist: "The Beatles",
                year: 1969,
                coverImageURL: nil,
                description: "The eleventh studio album by the English rock band the Beatles, released on 26 September 1969. It was the last album the group recorded, although Let It Be was the last album released before the band's dissolution in 1970.",
                spotifyURL: "spotify:album:0ETFjACtuP2ADo6LFhL6HN",
                appleMusicURL: "https://music.apple.com/us/album/abbey-road/1441133100"
            ),
            AlbumOfTheDay(
                title: "Kind of Blue",
                artist: "Miles Davis",
                year: 1959,
                coverImageURL: nil,
                description: "A studio album by American jazz trumpeter Miles Davis, released on August 17, 1959, by Columbia Records. It is regarded by many critics as the greatest jazz record, Davis's masterpiece, and one of the best albums of all time.",
                spotifyURL: "spotify:album:1weenld61qoidwYuZ1GESA",
                appleMusicURL: "https://music.apple.com/us/album/kind-of-blue/1440650935"
            ),
            AlbumOfTheDay(
                title: "The Dark Side of the Moon",
                artist: "Pink Floyd",
                year: 1973,
                coverImageURL: nil,
                description: "The eighth studio album by the English rock band Pink Floyd, released on 1 March 1973 by Harvest Records. It built on ideas explored in the band's earlier recordings and live shows, but lacks the extended instrumental excursions that characterised their earlier work.",
                spotifyURL: "spotify:album:4LH4d3cOWNNsVw41Gqt2kv",
                appleMusicURL: "https://music.apple.com/us/album/the-dark-side-of-the-moon/1065977164"
            )
        ]
    }
    
    // MARK: - CPTemplateApplicationSceneDelegate
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        setupCarPlayInterface()
    }
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }
    
    // MARK: - CarPlay Interface Setup
    
    private func setupCarPlayInterface() {
        guard let interfaceController = interfaceController else { return }
        
        // Create the main template with split view
        let mainTemplate = createMainTemplate()
        interfaceController.setRootTemplate(mainTemplate, animated: true)
    }
    
    private func createMainTemplate() -> CPTemplate {
        // Create grid buttons for album navigation
        let gridButtons = createGridButtons()
        
        // Create list template for the grid
        let gridTemplate = CPGridTemplate(title: "Album of the Day", gridButtons: gridButtons)
        
        return gridTemplate
    }
    
    private func createGridButtons() -> [CPGridButton] {
        var buttons: [CPGridButton] = []
        
        // Previous album button
        let previousButton = CPGridButton(titleVariants: ["Previous"], image: UIImage(systemName: "chevron.left")!) { [weak self] _ in
            DispatchQueue.main.async { self?.showPreviousAlbum() }
        }
        buttons.append(previousButton)
        
        // Current album display (center)
        let currentAlbum = albums[currentAlbumIndex]
        let albumButton = CPGridButton(
            titleVariants: [currentAlbum.title, currentAlbum.artist],
            image: UIImage(systemName: "music.note")!
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.showAlbumDetail() }
        }
        buttons.append(albumButton)
        
        // Next album button
        let nextButton = CPGridButton(titleVariants: ["Next"], image: UIImage(systemName: "chevron.right")!) { [weak self] _ in
            DispatchQueue.main.async { self?.showNextAlbum() }
        }
        buttons.append(nextButton)
        
        // Spotify button
        let spotifyButton = CPGridButton(
            titleVariants: ["Spotify"],
            image: UIImage(named: "SpotifyIcon") ?? UIImage(systemName: "play.circle")!
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.openSpotify() }
        }
        buttons.append(spotifyButton)
        
        // Apple Music button
        let appleMusicButton = CPGridButton(
            titleVariants: ["Apple Music"],
            image: UIImage(named: "AppleMusicIcon") ?? UIImage(systemName: "music.note")!
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.openAppleMusic() }
        }
        buttons.append(appleMusicButton)
        
        // About button
        let aboutButton = CPGridButton(
            titleVariants: ["About"],
            image: UIImage(systemName: "info.circle")!
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.showAboutSection() }
        }
        buttons.append(aboutButton)
        
        return buttons
    }
    
    // MARK: - Navigation Actions
    
    private func showPreviousAlbum() {
        currentAlbumIndex = (currentAlbumIndex - 1 + albums.count) % albums.count
        refreshInterface()
    }

    private func showNextAlbum() {
        currentAlbumIndex = (currentAlbumIndex + 1) % albums.count
        refreshInterface()
    }

    private func showAlbumDetail() {
        let currentAlbum = albums[currentAlbumIndex]

        // Create detail items
        var detailItems: [CPInformationItem] = []

        detailItems.append(CPInformationItem(
            title: "Artist",
            detail: currentAlbum.artist
        ))

        detailItems.append(CPInformationItem(
            title: "Year",
            detail: "\(currentAlbum.year)"
        ))

        detailItems.append(CPInformationItem(
            title: "Description",
            detail: currentAlbum.description
        ))

        // Create actions
        let actions = [
            CPTextButton(title: "Stream on Spotify", textStyle: .confirm) { [weak self] _ in
                DispatchQueue.main.async { self?.openSpotify() }
            },
            CPTextButton(title: "Stream on Apple Music", textStyle: .confirm) { [weak self] _ in
                DispatchQueue.main.async { self?.openAppleMusic() }
            },
            CPTextButton(title: "Back", textStyle: .cancel) { [weak self] _ in
                DispatchQueue.main.async { self?.interfaceController?.popTemplate(animated: true) }
            }
        ]

        // Create information template
        let detailTemplate = CPInformationTemplate(
            title: currentAlbum.title,
            layout: .twoColumn,
            items: detailItems,
            actions: actions
        )

        DispatchQueue.main.async { [weak self] in
            self?.interfaceController?.pushTemplate(detailTemplate, animated: true)
        }
    }
    
    private func openSpotify() {
        let currentAlbum = albums[currentAlbumIndex]
        
        if let spotifyURL = currentAlbum.spotifyURL,
           let url = URL(string: spotifyURL) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            // Fallback to search
            let searchQuery = "\(currentAlbum.artist) \(currentAlbum.title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "spotify:search:\(searchQuery)") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
    
    private func openAppleMusic() {
        let currentAlbum = albums[currentAlbumIndex]
        
        if let appleMusicURL = currentAlbum.appleMusicURL,
           let url = URL(string: appleMusicURL) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            // Fallback to search
            let searchQuery = "\(currentAlbum.artist) \(currentAlbum.title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://music.apple.com/us/search?term=\(searchQuery)") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
    
    private func showAboutSection() {
        let aboutItems = [
            CPInformationItem(
                title: "SecondSpin",
                detail: "Your vinyl collection manager"
            ),
            CPInformationItem(
                title: "Version",
                detail: "1.0"
            ),
            CPInformationItem(
                title: "Description",
                detail: "SecondSpin helps you catalog and discover music from your vinyl collection. Browse your collection, get reviews, and stream albums on your favorite services."
            )
        ]

        let actions = [
            CPTextButton(title: "Back", textStyle: .cancel) { [weak self] _ in
                DispatchQueue.main.async { self?.interfaceController?.popTemplate(animated: true) }
            }
        ]

        let aboutTemplate = CPInformationTemplate(
            title: "About SecondSpin",
            layout: .twoColumn,
            items: aboutItems,
            actions: actions
        )

        DispatchQueue.main.async { [weak self] in
            self?.interfaceController?.pushTemplate(aboutTemplate, animated: true)
        }
    }

    private func refreshInterface() {
        guard let interfaceController = interfaceController else { return }
        let newTemplate = CPGridTemplate(title: "Album of the Day", gridButtons: createGridButtons())
        DispatchQueue.main.async {
            interfaceController.setRootTemplate(newTemplate, animated: true)
        }
    }
}

#else

// Fallback implementation for non-CarPlay environments
@available(iOS 14.0, *)
class CarPlaySceneDelegate: NSObject {
    // Empty implementation that won't cause compilation errors
    // when CarPlay framework is not available
}

#endif
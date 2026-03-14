//
//  SearchResultsView.swift
//  SecondSpin
//
//  Display Discogs search results
//

import SwiftUI
import SwiftData

enum SearchType {
    case barcode
    case manual
}

struct SearchResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var existingReleases: [Release]

    let results: [DiscogsRelease]
    let searchType: SearchType

    @State private var selectedRelease: DiscogsRelease?
    @State private var selectedDiscogsDetail: DiscogsReleaseDetail?
    @State private var selectedExistingRelease: Release?
    @State private var isLoadingDetails = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            List(results) { result in
                SearchResultRow(result: result) {
                    addReleaseDirectly(result)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectRelease(result)
                }
            }
            .navigationTitle("Search Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isLoadingDetails {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)

                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Loading details...")
                            .font(.headline)
                    }
                    .padding(30)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 20)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .sheet(item: $selectedDiscogsDetail) { detail in
                DiscogsPreviewView(discogsDetail: detail)
            }
            .sheet(item: $selectedExistingRelease) { existingRelease in
                AddCopyView(release: existingRelease)
            }
        }
    }

    private func selectRelease(_ result: DiscogsRelease) {
        selectedRelease = result

        if let existing = existingReleases.first(where: { $0.discogsId == result.id }) {
            // Release already in collection – add another copy
            selectedExistingRelease = existing
        } else {
            // Fetch full details and show preview
            isLoadingDetails = true

            Task {
                do {
                    let details = try await DiscogsService.shared.getReleaseDetails(releaseId: result.id)

                    await MainActor.run {
                        isLoadingDetails = false
                        selectedDiscogsDetail = details
                    }
                } catch {
                    await MainActor.run {
                        isLoadingDetails = false
                        errorMessage = "Failed to load release details: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
        }
    }

    private func addReleaseDirectly(_ result: DiscogsRelease) {
        // Check if already in collection
        if existingReleases.contains(where: { $0.discogsId == result.id }) {
            // Show toast that it's already in collection
            appState.showToast("This album is already in your collection")
            return
        }
        
        // Create a basic release from search result data
        // Note: DiscogsRelease search results don't include artist info
        // We'll use "Unknown Artist" and try to fetch artist info later if needed
        let title = result.title
        
        // Try to parse artist from title (common patterns: "Artist - Title" or "Artist: Title")
        let artist = parseArtistFromTitle(title)
        
        // Use available image URLs
        let coverImageURL = result.coverImage ?? result.thumb ?? ""
        let thumbnailImageURL = result.thumb ?? result.coverImage ?? ""
        
        // Create new release with available data
        let release = Release(
            discogsId: result.id,
            title: title,
            artist: artist,
            year: Int(result.year ?? "0") ?? 0,
            label: result.label?.first ?? "Unknown Label",
            catalogNumber: nil, // Not available in search results
            coverImageURL: coverImageURL,
            thumbnailImageURL: thumbnailImageURL,
            allImageURLs: coverImageURL.isEmpty ? [] : [coverImageURL],
            genres: result.genre ?? [],
            styles: result.style ?? [],
            format: result.format?.first ?? "LP",
            formatDescriptions: [],
            country: result.country,
            barcode: nil, // Not available in search results
            tracklist: [],
            notes: nil
        )

        // Add first copy
        let copy = Copy()
        release.copies.append(copy)

        modelContext.insert(release)

        do {
            try modelContext.save()
            
            // Show toast and navigate to Collection tab
            appState.navigateToCollection(toast: "Added \"\(title)\" to your collection")
            
            // Fetch full details in the background to enrich the release
            Task {
                await fetchAndUpdateReleaseDetails(releaseId: result.id, release: release)
            }
            
        } catch {
            errorMessage = "Failed to save release: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func fetchAndUpdateReleaseDetails(releaseId: Int, release: Release) async {
        do {
            let details = try await DiscogsService.shared.getReleaseDetails(releaseId: releaseId)
            
            await MainActor.run {
                // Update the release with full details
                updateReleaseWithDetails(release: release, details: details)
                
                // Save the updated release
                try? modelContext.save()
                
                print("Successfully updated release \(release.title) with full Discogs details")
            }
            
            // If Discogs doesn't have images or we want better quality, try fetching from other sources
            if release.coverImageURL.isEmpty {
                await fetchAlternativeArtwork(release: release)
            }
            
        } catch {
            print("Failed to fetch Discogs details for release \(releaseId): \(error)")
            // Don't show error to user since basic release was already added
            
            // Still try to fetch alternative artwork even if Discogs details failed
            if release.coverImageURL.isEmpty {
                await fetchAlternativeArtwork(release: release)
            }
        }
    }
    
    private func fetchAlternativeArtwork(release: Release) async {
        do {
            let artworkURL = try await AlbumArtworkService.shared.fetchAlbumArtwork(
                artist: release.artist,
                album: release.title
            )
            
            await MainActor.run {
                // Update the release with the fetched artwork
                release.coverImageURL = artworkURL
                release.thumbnailImageURL = artworkURL
                try? modelContext.save()
            }
        } catch {
            print("Could not fetch artwork from alternative sources: \(error)")
        }
    }
    
    private func updateReleaseWithDetails(release: Release, details: DiscogsReleaseDetail) {
        // Update artist from details (more accurate than parsed title)
        if let artistName = details.artists.first?.name {
            release.artist = artistName
        }
        
        // Update year if available
        if let year = details.year {
            release.year = year
        }
        
        // Update label if available
        if let labelName = details.labels.first?.name {
            release.label = labelName
        }
        
        // Update catalog number if available
        if let catno = details.labels.first?.catno {
            release.catalogNumber = catno
        }
        
        // Update genres and styles
        if let genres = details.genres {
            release.genres = genres
        }
        
        if let styles = details.styles {
            release.styles = styles
        }
        
        // Update format and descriptions
        if let format = details.formats?.first?.name {
            release.format = format
        }
        
        if let descriptions = details.formats?.first?.descriptions {
            release.formatDescriptions = descriptions
        }
        
        // Update country
        if let country = details.country {
            release.country = country
        }
        
        // Update barcode
        if let barcode = details.identifiers?.first(where: { $0.type == "Barcode" })?.value {
            release.barcode = barcode
        }
        
        // Update tracklist
        if let discogsTracklist = details.tracklist {
            release.tracklist = discogsTracklist.map { track in
                Track(position: track.position, title: track.title, duration: track.duration)
            }
        }
        
        // Update notes
        if let notes = details.notes {
            release.notes = notes
        }
        
        // Update images if better ones are available
        if let primaryImage = details.images?.first(where: { $0.type == "primary" }) {
            if !primaryImage.uri.isEmpty {
                release.coverImageURL = primaryImage.uri
                release.thumbnailImageURL = primaryImage.uri150 ?? primaryImage.uri
            }
        } else if let firstImage = details.images?.first {
            if !firstImage.uri.isEmpty {
                release.coverImageURL = firstImage.uri
                release.thumbnailImageURL = firstImage.uri150 ?? firstImage.uri
            }
        }
        
        // Update all image URLs
        if let images = details.images {
            let allImageURLs = images.compactMap { $0.uri.isEmpty ? nil : $0.uri }
            if !allImageURLs.isEmpty {
                release.allImageURLs = allImageURLs
            }
        }
    }
    
    private func parseArtistFromTitle(_ title: String) -> String {
        // Common patterns in Discogs search results:
        // 1. "Artist - Title"
        // 2. "Artist: Title"
        // 3. "Artist / Title"
        
        let patterns = [" - ", ": ", " / "]
        
        for pattern in patterns {
            if let range = title.range(of: pattern) {
                let artistPart = title[..<range.lowerBound]
                return String(artistPart).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return "Unknown Artist"
    }
    
    private func addRelease(from details: DiscogsReleaseDetail) {
        let artist = details.artists.first?.name ?? "Unknown Artist"
        let title = details.title
        
        // Get primary image from Discogs
        let coverImageURL = details.images?.first(where: { $0.type == "primary" })?.uri ?? details.images?.first?.uri ?? ""
        let thumbnailImageURL = details.images?.first(where: { $0.type == "primary" })?.uri150 ?? details.images?.first?.uri150 ?? ""
        // Collect all full-size image URLs (primary first, then secondaries)
        let allImageURLs: [String] = {
            guard let images = details.images else { return coverImageURL.isEmpty ? [] : [coverImageURL] }
            let sorted = images.sorted { a, _ in a.type == "primary" }
            return sorted.compactMap { $0.uri.isEmpty ? nil : $0.uri }
        }()

        // Create new release with initial data
        let release = Release(
            discogsId: details.id,
            title: title,
            artist: artist,
            year: details.year ?? 0,
            label: details.labels.first?.name ?? "Unknown Label",
            catalogNumber: details.labels.first?.catno,
            coverImageURL: coverImageURL,
            thumbnailImageURL: thumbnailImageURL,
            allImageURLs: allImageURLs,
            genres: details.genres ?? [],
            styles: details.styles ?? [],
            format: details.formats?.first?.name ?? "LP",
            formatDescriptions: details.formats?.first?.descriptions ?? [],
            country: details.country,
            barcode: details.identifiers?.first(where: { $0.type == "Barcode" })?.value,
            tracklist: details.tracklist?.map { Track(position: $0.position, title: $0.title, duration: $0.duration) } ?? [],
            notes: details.notes
        )

        // Add first copy
        let copy = Copy()
        release.copies.append(copy)

        modelContext.insert(release)

        do {
            try modelContext.save()
            
            // If Discogs doesn't have images, try fetching from other sources asynchronously
            if coverImageURL.isEmpty {
                Task {
                    do {
                        let artworkURL = try await AlbumArtworkService.shared.fetchAlbumArtwork(
                            artist: artist,
                            album: title
                        )
                        
                        await MainActor.run {
                            // Update the release with the fetched artwork
                            release.coverImageURL = artworkURL
                            release.thumbnailImageURL = artworkURL
                            try? modelContext.save()
                        }
                    } catch {
                        print("Could not fetch artwork from alternative sources: \(error)")
                    }
                }
            }
            
            // Navigate to Collection tab with a toast confirmation
            appState.navigateToCollection(toast: "Added \"\(title)\" by \(artist)")
        } catch {
            errorMessage = "Failed to save release: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: DiscogsRelease
    var onAddToCollection: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail - prefer coverImage over thumb for better quality
            let imageURL = result.coverImage ?? result.thumb
            ZStack(alignment: .center) {
                // Background rectangle
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                
                // Album art image or placeholder
                if let urlString = imageURL, let url = URL(string: urlString), !urlString.isEmpty {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 60, maxHeight: 60)
                    } placeholder: {
                        // Show loading placeholder
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                            .font(.system(size: 24))
                    }
                } else {
                    // Placeholder icon when no image URL
                    Image(systemName: "music.note")
                        .foregroundColor(.gray)
                        .font(.system(size: 24))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(2)

                if let year = result.year {
                    Text(year)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Format and Country on same line
                HStack(spacing: 4) {
                    if let formats = result.format, !formats.isEmpty {
                        Text(formats.joined(separator: " · "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let country = result.country {
                        if result.format?.isEmpty == false {
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(country)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Add to Collection button (circled +)
            Button(action: {
                onAddToCollection?()
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    let sampleResults = [
        DiscogsRelease(
            id: 1,
            title: "Dark Side of the Moon",
            year: "1973",
            thumb: nil,
            coverImage: nil,
            resourceUrl: nil,
            format: ["LP"],
            label: ["Harvest"],
            genre: ["Rock"],
            style: ["Prog Rock"],
            country: "UK"
        )
    ]

    return SearchResultsView(results: sampleResults, searchType: .manual)
        .environmentObject(AppState())
        .modelContainer(for: [Release.self], inMemory: true)
}

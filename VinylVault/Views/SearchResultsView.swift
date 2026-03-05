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
    @State private var selectedExistingRelease: Release?
    @State private var isLoadingDetails = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            List(results) { result in
                Button(action: {
                    selectRelease(result)
                }) {
                    SearchResultRow(result: result)
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
            // Fetch full details and add new release
            isLoadingDetails = true

            Task {
                do {
                    let details = try await DiscogsService.shared.getReleaseDetails(releaseId: result.id)

                    await MainActor.run {
                        isLoadingDetails = false
                        addRelease(from: details)
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
            coverImageURL: coverImageURL,
            thumbnailImageURL: thumbnailImageURL,
            allImageURLs: allImageURLs,
            genres: details.genres ?? [],
            styles: details.styles ?? [],
            format: details.formats?.first?.name ?? "LP",
            formatDescriptions: details.formats?.first?.descriptions ?? [],
            country: details.country,
            barcode: details.identifiers?.first(where: { $0.type == "Barcode" })?.value,
            tracklist: details.tracklist?.map { Track(position: $0.position, title: $0.title, duration: $0.duration) } ?? []
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

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail - prefer coverImage over thumb for better quality
            let imageURL = result.coverImage ?? result.thumb
            CachedAsyncImage(url: URL(string: imageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    )
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

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
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

//
//  ReleaseDetailView.swift
//  VinylVault
//
//  Detailed view of a release
//

import SwiftUI
import SwiftData

struct ReleaseDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var release: Release
    
    @State private var showDeleteConfirmation = false
    @State private var wikipediaDescription: String?
    @State private var wikipediaURL: URL?
    @State private var wikipediaReviewScores: [AlbumReviewScore] = []
    @State private var isLoadingWikipedia = false
    @State private var showFullDescription = false
    @State private var selectedCopy: Copy?
    @State private var showGallery = false
    @State private var galleryStartIndex = 0
    @State private var isVerifyingLinks = false
    @State private var showAddCopy = false
    @State private var musicBrainzRating: MusicBrainzRating?
    @State private var musicBrainzGenres: [MusicBrainzGenre] = []
    @State private var albumReviews: [AlbumReview] = []
    @State private var isLoadingMusicBrainz = false
    @State private var isLoadingReviews = false
    @State private var musicBrainzMBID: String?
    @State private var expandedReviewId: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Cover Image - tappable, opens full-screen gallery
                Button {
                    galleryStartIndex = 0
                    showGallery = true
                } label: {
                    CachedAsyncImage(url: URL(string: release.coverImageURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                            )
                    }
                    .frame(maxHeight: 350)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 6)
                    // "Tap to view" badge when multiple images exist
                    .overlay(alignment: .bottomTrailing) {
                        if release.allImageURLs.count > 1 {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.caption2)
                                Text("\(release.allImageURLs.count)")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55))
                            .clipShape(Capsule())
                            .padding(10)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                // Basic Info
                VStack(alignment: .leading, spacing: 12) {
                    Text(release.title)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(release.artist)
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    // Line 1: Format and Year
                    HStack(spacing: 4) {
                        Text(release.fullFormatDisplay)
                        if release.year > 0 {
                            Text(String(release.year))
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    
                    // Line 2: Label, Catalog Number, Country
                    HStack(spacing: 4) {
                        Text(release.label)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(-1)
                        if let catalogNumber = release.catalogNumber {
                            Text("·")
                            Text(catalogNumber)
                        }
                        if let country = release.country {
                            Text("·")
                            Text(country)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    
                    // Genres and Styles
                    if !release.genres.isEmpty || !release.styles.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(release.genres + release.styles, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                
                // Tracklist + streaming icons header
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Text("Tracklist")
                            .font(.headline)
                        Spacer()
                        HStack(spacing: 14) {
                            Button {
                                StreamingLinkService.shared.openSpotify(
                                    release: release,
                                    artist: release.artist,
                                    album: release.title
                                )
                            } label: {
                                ZStack {
                                    Image("SpotifyIcon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                    if isVerifyingLinks {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 28, height: 28)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                }
                            }
                            Button {
                                StreamingLinkService.shared.openAppleMusic(
                                    release: release,
                                    artist: release.artist,
                                    album: release.title
                                )
                            } label: {
                                ZStack {
                                    Image("AppleMusicIcon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                    if isVerifyingLinks {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 28, height: 28)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                }
                            }
                        }
                    }

                    ForEach(release.tracklist, id: \.position) { track in
                        HStack {
                            Text(track.position)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 30, alignment: .leading)

                            Text(track.title)
                                .font(.subheadline)

                            Spacer()

                            if let duration = track.duration {
                                Text(duration)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                
                // MusicBrainz Rating Section
                if isLoadingMusicBrainz {
                    HStack {
                        ProgressView()
                        Text("Loading rating...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else if let rating = musicBrainzRating, rating.votesCount > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Community Rating")
                            .font(.headline)
                        
                        HStack(spacing: 8) {
                            // Star rating display
                            HStack(spacing: 4) {
                                ForEach(0..<5) { index in
                                    Image(systemName: index < Int((rating.value ?? 0).rounded()) ? "star.fill" : "star")
                                        .foregroundColor(.yellow)
                                        .font(.title3)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rating.displayRating)
                                    .font(.headline)
                                Text("\(rating.votesCount) votes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // MusicBrainz genres (if different from Discogs)
                        if !musicBrainzGenres.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(musicBrainzGenres.prefix(5)) { genre in
                                        HStack(spacing: 4) {
                                            Text(genre.name)
                                            Text("(\(genre.count))")
                                                .font(.caption2)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.15))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                }
                
                // Reviews Section
                if isLoadingReviews {
                    HStack {
                        ProgressView()
                        Text("Loading reviews...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else if !albumReviews.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Reviews (\(albumReviews.count))")
                            .font(.headline)
                        
                        ForEach(albumReviews) { review in
                            ReviewCardView(
                                review: review,
                                isExpanded: expandedReviewId == review.id
                            ) {
                                withAnimation {
                                    expandedReviewId = expandedReviewId == review.id ? nil : review.id
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                }
                
                // Critical Reception Section (Wikipedia Professional Ratings)
                if !wikipediaReviewScores.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Critical Reception")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            ForEach(wikipediaReviewScores) { score in
                                HStack(alignment: .top) {
                                    Text(score.source)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Text(score.rating)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        
                        if let wikiURL = wikipediaURL {
                            HStack {
                                Spacer()
                                Link(destination: wikiURL) {
                                    HStack(spacing: 4) {
                                        Text("View on Wikipedia")
                                            .font(.caption)
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                }
                
                // Wikipedia Section
                if isLoadingWikipedia {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let description = wikipediaDescription {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About")
                            .font(.headline)
                        
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(showFullDescription ? nil : 5)
                        
                        HStack(alignment: .center) {
                            Button(action: {
                                withAnimation {
                                    showFullDescription.toggle()
                                }
                            }) {
                                Text(showFullDescription ? "Show Less" : "Read More")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            if let wikiURL = wikipediaURL {
                                Spacer()
                                Link(destination: wikiURL) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(.systemGray5))
                                            .frame(width: 28, height: 28)
                                        Text("W")
                                            .font(.system(size: 13, weight: .bold, design: .serif))
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                }
                
                // Copies Section
                if release.copyCount > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Your Copies (\(release.copyCount))")
                                .font(.headline)
                            Spacer()
                            Button {
                                showAddCopy = true
                            } label: {
                                Label("Add Copy", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                        }

                        ForEach(release.copies) { copy in
                            CopyRowView(copy: copy)
                                .onTapGesture {
                                    selectedCopy = copy
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                }
                
                // Delete Button
                Button(role: .destructive, action: {
                    showDeleteConfirmation = true
                }) {
                    Label("Remove from Collection", systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .padding(.bottom, 32)   // clear tab bar + safe area
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAllData()
        }
        .task {
            guard !release.streamingLinksVerified else { return }
            isVerifyingLinks = true
            await StreamingLinkService.shared.verifyAndUpdateLinks(release: release)
            isVerifyingLinks = false
        }
        .confirmationDialog("Remove Release", isPresented: $showDeleteConfirmation) {
            Button("Remove", role: .destructive) {
                deleteRelease()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the release and all copies from your collection.")
        }
        .sheet(item: $selectedCopy) { copy in
            EditCopyView(copy: copy)
        }
        .sheet(isPresented: $showAddCopy) {
            AddCopyView(release: release)
        }
        .fullScreenCover(isPresented: $showGallery) {
            ImageGalleryView(
                imageURLs: release.allImageURLs.isEmpty ? [release.coverImageURL] : release.allImageURLs,
                initialIndex: galleryStartIndex
            )
        }
    }
    
    private func loadAllData() {
        // Skip if already loaded
        guard wikipediaDescription == nil && musicBrainzRating == nil else { return }
        
        isLoadingWikipedia = true
        isLoadingMusicBrainz = true
        isLoadingReviews = true
        
        Task {
            // Load Wikipedia and MusicBrainz data concurrently
            async let wikipediaResult = fetchWikipediaData()
            async let musicBrainzResult = fetchMusicBrainzData()
            
            // Await both results
            let (wikiData, mbData) = await (wikipediaResult, musicBrainzResult)
            
            // Update UI on main actor
            await MainActor.run {
                // Wikipedia data
                if let wiki = wikiData {
                    wikipediaDescription = wiki.extract
                    wikipediaURL = wiki.pageURL
                    wikipediaReviewScores = wiki.reviewScores
                }
                isLoadingWikipedia = false
                
                // MusicBrainz data
                if let mb = mbData {
                    musicBrainzRating = mb.rating
                    musicBrainzGenres = mb.genres
                    musicBrainzMBID = mb.mbid
                    albumReviews = mb.reviews
                }
                isLoadingMusicBrainz = false
                isLoadingReviews = false
            }
        }
    }
    
    private func fetchWikipediaData() async -> WikipediaAlbumResult? {
        do {
            return try await WikipediaService.shared.resolveValidatedPage(
                albumTitle: release.title,
                artist: release.artist,
                year: release.year > 0 ? release.year : nil
            )
        } catch {
            print("Error loading Wikipedia data: \(error)")
            return nil
        }
    }
    
    private func fetchMusicBrainzData() async -> (rating: MusicBrainzRating?, genres: [MusicBrainzGenre], mbid: String?, reviews: [AlbumReview]) {
        do {
            // First check if we have a cached MBID
            let cachedMBID = await MusicBrainzService.shared.getCachedMBID(
                artist: release.artist,
                album: release.title
            )
            
            // If we have cached MBID, try to get cached data
            if let mbid = cachedMBID,
               let cachedData = await MusicBrainzService.shared.getCachedData(mbid: mbid) {
                // Use cached rating and genres
                
                // Try to get cached reviews
                if let cachedReviews = await CritiqueBrainzService.shared.getCachedReviews(mbid: mbid) {
                    return (cachedData.rating, cachedData.genres, mbid, cachedReviews)
                } else {
                    // Fetch reviews from API if not cached
                    let reviews = (try? await CritiqueBrainzService.shared.fetchReviews(mbid: mbid, limit: 5)) ?? []
                    return (cachedData.rating, cachedData.genres, mbid, reviews)
                }
            }
            
            // No cache available, fetch from API
            let result = try await MusicBrainzService.shared.getRatingAndGenres(
                artist: release.artist,
                album: release.title
            )
            
            // If we got an MBID, fetch reviews
            var reviews: [AlbumReview] = []
            if let mbid = result.mbid {
                reviews = (try? await CritiqueBrainzService.shared.fetchReviews(mbid: mbid, limit: 5)) ?? []
            }
            
            return (result.rating, result.genres, result.mbid, reviews)
        } catch {
            print("Error loading MusicBrainz data: \(error)")
            return (nil, [], nil, [])
        }
    }
    
    private func deleteRelease() {
        modelContext.delete(release)
        dismiss()
    }
}

// MARK: - Copy Row View

struct CopyRowView: View {
    let copy: Copy
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(copy.condition)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if let price = copy.purchasePrice {
                    Text("$\(String(format: "%.2f", price))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if !copy.notes.isEmpty {
                Text(copy.notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Text(copy.dateAdded.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    @MainActor
    func makePreview() -> some View {
        // Helper view to use @Query to fetch the release safely for the preview
        struct PreviewWrapper: View {
            @Query private var releases: [Release]
            
            var body: some View {
                if let release = releases.first {
                    ReleaseDetailView(release: release)
                } else {
                    ContentUnavailableView("Release Not Found", systemImage: "questionmark.diamond")
                }
            }
        }
        
        let container = try! ModelContainer(for: Release.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        
        // Insert a sample release
        let sampleRelease = Release(
            discogsId: 1,
            title: "Abbey Road",
            artist: "The Beatles",
            year: 1969,
            label: "Apple Records",
            coverImageURL: "",
            thumbnailImageURL: "",
            genres: ["Rock", "Pop"],
            styles: ["Pop Rock"],
            format: "LP",
            country: "UK",
            barcode: "1234567890",
            tracklist: [
                Track(position: "A1", title: "Come Together", duration: "4:20"),
                Track(position: "A2", title: "Something", duration: "3:03")
            ]
        )
        container.mainContext.insert(sampleRelease)
        
        return NavigationStack {
            PreviewWrapper()
        }
        .modelContainer(container)
    }
    
    return makePreview()
}

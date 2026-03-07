//
//  CollectionView.swift
//  VinylVault
//
//  My Collection screen with grid/list views
//

import SwiftUI
import SwiftData

enum CollectionViewMode {
    case grid
    case list
}

enum SortOption: String, CaseIterable {
    case random = "Random"
    case artist = "Artist"
    case title = "Title"
    case year = "Year"
    case dateAdded = "Date Added"
}

struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var releases: [Release]
    
    @State private var viewMode: CollectionViewMode = .grid
    @State private var sortOption: SortOption = .random
    @State private var searchText = ""
    @State private var selectedGenre: String?
    
    // Cached filtered and sorted results
    @State private var filteredAndSortedReleases: [Release] = []
    @State private var allGenres: [String] = []
    @State private var showGenreBrowser = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View Mode Toggle
                Picker("View Mode", selection: $viewMode) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(CollectionViewMode.grid)
                    Label("List", systemImage: "list.bullet").tag(CollectionViewMode.list)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if releases.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        if viewMode == .grid {
                            gridView
                        } else {
                            listView
                        }
                    }
                }
            }
            .navigationTitle("My Collection")
            .searchable(text: $searchText, prompt: "Search collection")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showGenreBrowser = true
                    } label: {
                        Image(systemName: "tag.circle")
                    }
                    .disabled(releases.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Sort By", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        
                        Divider()
                        
                        Menu("Filter by Genre") {
                            Button("All Genres") {
                                selectedGenre = nil
                            }
                            
                            ForEach(allGenres, id: \.self) { genre in
                                Button(genre) {
                                    selectedGenre = genre
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .onAppear {
                updateGenres()
                updateFilteredReleases()
            }
            .onChange(of: releases.count) { _, _ in
                updateGenres()
                updateFilteredReleases()
            }
            .onChange(of: searchText) { _, _ in
                updateFilteredReleases()
            }
            .onChange(of: sortOption) { oldValue, newValue in
                // Only reshuffle when the user explicitly switches TO Random
                updateFilteredReleases(reshuffle: newValue == .random)
            }
            .onChange(of: selectedGenre) { _, _ in
                updateFilteredReleases()
            }
            .sheet(isPresented: $showGenreBrowser) {
                GenreBrowserSheet(allTags: allGenres)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateGenres() {
        // Collect both genres and styles so the browser shows every tag
        allGenres = Array(Set(releases.flatMap { $0.genres + $0.styles })).sorted()
    }
    
    /// Update the displayed list, optionally re-shuffling when sort is Random.
    /// Pass `reshuffle: true` only when the user explicitly picks "Random" from the sort menu.
    private func updateFilteredReleases(reshuffle: Bool = false) {
        var filtered = releases
        
        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { release in
                release.title.localizedCaseInsensitiveContains(searchText) ||
                release.artist.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Genre filter
        if let genre = selectedGenre {
            filtered = filtered.filter { $0.genres.contains(genre) }
        }
        
        // Sorting
        switch sortOption {
        case .random:
            if reshuffle || filteredAndSortedReleases.isEmpty {
                // Only re-shuffle when explicitly requested or on first load
                filtered.shuffle()
            } else {
                // Preserve existing random order — just remove items that no longer match
                let existingOrder = filteredAndSortedReleases
                let filteredIDs = Set(filtered.map { $0.id })
                var stable = existingOrder.filter { filteredIDs.contains($0.id) }
                // Append any newly added releases (not yet in the stable order) at the end
                let stableIDs = Set(stable.map { $0.id })
                stable += filtered.filter { !stableIDs.contains($0.id) }
                filtered = stable
            }
        case .artist:
            filtered.sort { $0.artist.localizedCompare($1.artist) == .orderedAscending }
        case .title:
            filtered.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .year:
            filtered.sort { $0.year < $1.year }
        case .dateAdded:
            filtered.sort { $0.dateAdded > $1.dateAdded }
        }
        
        filteredAndSortedReleases = filtered
    }
    
    // MARK: - Grid View
    
    private var gridView: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(filteredAndSortedReleases) { release in
                NavigationLink(destination: ReleaseDetailView(release: release)) {
                    GridItemView(release: release)
                }
            }
        }
        .padding()
    }
    
    // MARK: - List View
    
    private var listView: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredAndSortedReleases) { release in
                NavigationLink(destination: ReleaseDetailView(release: release)) {
                    ListItemView(release: release)
                }
                .buttonStyle(.plain)
                
                Divider()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Records Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start building your collection by\nadding your first vinyl record")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Grid Item View

struct GridItemView: View {
    let release: Release
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Square filler background — visible as letterbox bars on portrait artwork
                Color.gray.opacity(0.15)

                // Cover Image — fits within the square; portrait images get side bars
                CachedAsyncImage(url: URL(string: release.coverImageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Copy Count Badge
                if release.copyCount > 1 {
                    Text("\(release.copyCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .padding(8)
                }
            }
            // Force the whole ZStack to be a square, then clip to rounded rect
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Title
            Text(release.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundColor(.primary)
            
            // Artist
            Text(release.artist)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // Format, Year, Country
            HStack(spacing: 4) {
                Text(release.fullFormatDisplay)
                if release.year > 0 {
                    Text("·")
                    Text(release.year.formatted(.number.grouping(.never)))
                }
                if let country = release.country {
                    Text("·")
                    Text(country)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
    }
}

// MARK: - List Item View

struct ListItemView: View {
    let release: Release

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            CachedAsyncImage(url: URL(string: release.thumbnailImageURL)) { image in
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
                Text(release.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)

                Text(release.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if release.year > 0 {
                        Text(release.year.formatted(.number.grouping(.never)))
                        Text("·")
                    }
                    Text(release.fullFormatDisplay)
                    if let country = release.country {
                        Text("·")
                        Text(country)
                    }
                    Text("·")
                    Text(release.label)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer()

            // Copy count badge
            if release.copyCount > 1 {
                Text("\(release.copyCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
    }
}

#Preview {
    CollectionView()
        .modelContainer(for: [Release.self], inMemory: true)
}
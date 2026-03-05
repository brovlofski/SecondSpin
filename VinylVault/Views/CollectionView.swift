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
    case artist = "Artist"
    case title = "Title"
    case year = "Year"
    case dateAdded = "Date Added"
}

struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var releases: [Release]
    
    @State private var viewMode: CollectionViewMode = .grid
    @State private var sortOption: SortOption = .artist
    @State private var searchText = ""
    @State private var selectedGenre: String?
    
    private var filteredAndSortedReleases: [Release] {
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
        case .artist:
            filtered.sort { $0.artist.localizedCompare($1.artist) == .orderedAscending }
        case .title:
            filtered.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .year:
            filtered.sort { $0.year < $1.year }
        case .dateAdded:
            filtered.sort { $0.dateAdded > $1.dateAdded }
        }
        
        return filtered
    }
    
    private var allGenres: [String] {
        Array(Set(releases.flatMap { $0.genres })).sorted()
    }
    
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
        }
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
                // Square background box with gray color
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Cover Image - natural aspect ratio centered in square box
                CachedAsyncImage(url: URL(string: release.coverImageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color.clear)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                
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
            
            // Format and Year
            HStack(spacing: 4) {
                Text(release.format)
                Text("·")
                Text(release.year.formatted(.number.grouping(.never)))
            }
            .font(.caption)
            .foregroundColor(.secondary)
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
                    Text(release.year.formatted(.number.grouping(.never)))
                    Text("·")
                    Text(release.format)
                    Text("·")
                    Text(release.label)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundColor(.secondary)
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
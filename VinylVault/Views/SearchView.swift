//
//  SearchView.swift
//  VinylVault
//
//  Search within collection
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @Query private var releases: [Release]
    
    @State private var searchText = ""
    @State private var searchScope: SearchScope = .all
    
    private enum SearchScope: String, CaseIterable {
        case all = "All"
        case artist = "Artist"
        case title = "Title"
        case label = "Label"
        case genre = "Genre"
    }
    
    private var searchResults: [Release] {
        guard !searchText.isEmpty else { return [] }
        
        let query = searchText.lowercased()
        
        return releases.filter { release in
            switch searchScope {
            case .all:
                return release.title.lowercased().contains(query) ||
                       release.artist.lowercased().contains(query) ||
                       release.label.lowercased().contains(query) ||
                       release.genres.contains(where: { $0.lowercased().contains(query) })
            case .artist:
                return release.artist.lowercased().contains(query)
            case .title:
                return release.title.lowercased().contains(query)
            case .label:
                return release.label.lowercased().contains(query)
            case .genre:
                return release.genres.contains(where: { $0.lowercased().contains(query) })
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if searchText.isEmpty {
                    emptySearchView
                } else if searchResults.isEmpty {
                    noResultsView
                } else {
                    List(searchResults) { release in
                        NavigationLink(destination: ReleaseDetailView(release: release)) {
                            ListItemView(release: release)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search your collection")
            .searchScopes($searchScope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
        }
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Search Your Collection")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Find albums by artist, title, label, or genre")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Results")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Try adjusting your search or scope")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

#Preview {
    SearchView()
        .modelContainer(for: [Release.self], inMemory: true)
}
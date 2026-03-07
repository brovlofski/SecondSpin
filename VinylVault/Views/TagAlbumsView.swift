//
//  TagAlbumsView.swift
//  VinylVault
//
//  Shows all albums in the collection that share a given genre or style tag.
//

import SwiftUI
import SwiftData

struct TagAlbumsView: View {
    let tag: String

    @Query private var allReleases: [Release]

    private var releases: [Release] {
        allReleases.filter { $0.genres.contains(tag) || $0.styles.contains(tag) }
                   .sorted { $0.artist.localizedCompare($1.artist) == .orderedAscending }
    }

    var body: some View {
        Group {
            if releases.isEmpty {
                ContentUnavailableView(
                    "No Albums",
                    systemImage: "tag",
                    description: Text("No albums in your collection are tagged "\(tag)".")
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 16
                    ) {
                        ForEach(releases) { release in
                            NavigationLink(destination: ReleaseDetailView(release: release)) {
                                GridItemView(release: release)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(tag)
        .navigationBarTitleDisplayMode(.large)
    }
}
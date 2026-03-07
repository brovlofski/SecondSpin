//
//  GenreBrowserSheet.swift
//  VinylVault
//
//  A sheet that lists every genre/style tag in the collection.
//  Tapping a row navigates to TagAlbumsView for that tag.
//

import SwiftUI
import SwiftData

struct GenreBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// All tags (genres + styles) collected from the collection, sorted alphabetically.
    let allTags: [String]

    /// Count of releases per tag, computed once on appear.
    @Query private var allReleases: [Release]

    private var tagCounts: [(tag: String, count: Int)] {
        allTags.map { tag in
            let count = allReleases.filter {
                $0.genres.contains(tag) || $0.styles.contains(tag)
            }.count
            return (tag: tag, count: count)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allTags.isEmpty {
                    ContentUnavailableView(
                        "No Tags",
                        systemImage: "tag.slash",
                        description: Text("Add albums to your collection to see genres and styles here.")
                    )
                } else {
                    List(tagCounts, id: \.tag) { item in
                        NavigationLink(destination: TagAlbumsView(tag: item.tag)) {
                            HStack {
                                Image(systemName: "tag")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)

                                Text(item.tag)
                                    .font(.body)

                                Spacer()

                                Text("\(item.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Browse by Tag")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
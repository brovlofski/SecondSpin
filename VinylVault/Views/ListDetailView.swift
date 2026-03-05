//
//  ListDetailView.swift
//  VinylVault
//
//  Detailed view of a list with albums
//

import SwiftUI
import SwiftData

struct ListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allReleases: [Release]
    
    @Bindable var list: RecordList
    
    @State private var showAddAlbums = false
    @State private var showEditList = false
    
    var body: some View {
        Group {
            if list.releases.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(list.releases) { release in
                            NavigationLink(destination: ReleaseDetailView(release: release)) {
                                GridItemView(release: release)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            removeRelease(release)
                                        } label: {
                                            Label("Remove from List", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        showAddAlbums = true
                    }) {
                        Label("Add Albums", systemImage: "plus")
                    }
                    
                    Button(action: {
                        showEditList = true
                    }) {
                        Label("Edit List", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddAlbums) {
            AddAlbumsToListView(list: list, availableReleases: availableReleases)
        }
        .sheet(isPresented: $showEditList) {
            EditListView(list: list)
        }
    }
    
    private var availableReleases: [Release] {
        allReleases.filter { release in
            !list.releases.contains(where: { $0.id == release.id })
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Albums in List")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add albums to start building this list")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showAddAlbums = true
            }) {
                Label("Add Albums", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top)
        }
        .padding(40)
    }
    
    private func removeRelease(_ release: Release) {
        if let index = list.releases.firstIndex(where: { $0.id == release.id }) {
            list.releases.remove(at: index)
        }
    }
}

// MARK: - Add Albums to List

struct AddAlbumsToListView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var list: RecordList
    let availableReleases: [Release]
    
    @State private var selectedReleases: Set<Release.ID> = []
    
    var body: some View {
        NavigationStack {
            List(availableReleases) { release in
                Button(action: {
                    if selectedReleases.contains(release.id) {
                        selectedReleases.remove(release.id)
                    } else {
                        selectedReleases.insert(release.id)
                    }
                }) {
                    HStack {
                        ListItemView(release: release)
                        
                        Spacer()
                        
                        if selectedReleases.contains(release.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Add Albums")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addSelectedReleases()
                    }
                    .disabled(selectedReleases.isEmpty)
                }
            }
        }
    }
    
    private func addSelectedReleases() {
        for releaseId in selectedReleases {
            if let release = availableReleases.first(where: { $0.id == releaseId }) {
                list.releases.append(release)
            }
        }
        
        dismiss()
    }
}

// MARK: - Edit List

struct EditListView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var list: RecordList
    
    var body: some View {
        NavigationStack {
            Form {
                Section("List Details") {
                    TextField("Name", text: $list.name)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Description", text: $list.listDescription, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle("Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    let container = try! ModelContainer(for: RecordList.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let list = RecordList(name: "Favorites", listDescription: "My favorite albums")
    container.mainContext.insert(list)
    
    return NavigationStack {
        ListDetailView(list: list)
    }
    .modelContainer(container)
}
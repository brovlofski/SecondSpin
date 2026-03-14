//
//  ListsView.swift
//  VinylVault
//
//  User-defined lists
//

import SwiftUI
import SwiftData

struct ListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecordList.orderIndex) private var allLists: [RecordList]
    
    // Separate system lists from user lists
    private var systemLists: [RecordList] {
        allLists.filter { $0.isSystemList }
    }
    
    private var userLists: [RecordList] {
        allLists.filter { !$0.isSystemList }
    }
    
    private var lists: [RecordList] {
        // System lists first, then user lists
        systemLists + userLists
    }
    
    @State private var showCreateList = false
    @State private var newListName = ""
    @State private var newListDescription = ""
    
    var body: some View {
        NavigationStack {
            Group {
                if lists.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(lists) { list in
                            NavigationLink(destination: ListDetailView(list: list)) {
                                ListRowView(list: list)
                            }
                        }
                        .onMove(perform: moveList)
                        .onDelete(perform: deleteList)
                    }
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showCreateList = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
                
                if !lists.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showCreateList) {
                NavigationStack {
                    Form {
                        Section("List Details") {
                            TextField("Name", text: $newListName)
                                .textInputAutocapitalization(.words)
                            
                            TextField("Description (Optional)", text: $newListDescription, axis: .vertical)
                                .lineLimit(3...5)
                        }
                    }
                    .navigationTitle("New List")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showCreateList = false
                                newListName = ""
                                newListDescription = ""
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Create") {
                                createList()
                            }
                            .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Lists Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create custom lists to organize\nyour vinyl collection")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                showCreateList = true
            }) {
                Label("Create List", systemImage: "plus")
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
    
    // MARK: - List Management
    
    private func createList() {
        // Calculate order index for new user list (after all system lists)
        let userListCount = userLists.count
        let list = RecordList(
            name: newListName.trimmingCharacters(in: .whitespaces),
            listDescription: newListDescription.trimmingCharacters(in: .whitespaces),
            orderIndex: userListCount  // Positive index for user lists
        )
        
        modelContext.insert(list)
        
        showCreateList = false
        newListName = ""
        newListDescription = ""
    }
    
    private func moveList(from source: IndexSet, to destination: Int) {
        // Prevent moving system lists
        let sourceLists = source.map { lists[$0] }
        let containsSystemList = sourceLists.contains { $0.isSystemList }
        
        if containsSystemList {
            // Don't allow moving system lists
            return
        }
        
        var revisedLists = lists
        revisedLists.move(fromOffsets: source, toOffset: destination)
        
        // Update order indices, keeping system lists at the top
        var currentIndex = 0
        for list in revisedLists {
            if list.isSystemList {
                // System lists keep negative indices to stay at top
                list.orderIndex = -1 - currentIndex
            } else {
                // User lists get positive indices starting from 0
                list.orderIndex = currentIndex
            }
            currentIndex += 1
        }
    }
    
    private func deleteList(at offsets: IndexSet) {
        for index in offsets {
            let list = lists[index]
            // Prevent deletion of system lists
            if !list.isSystemList {
                modelContext.delete(list)
            }
        }
    }
}

// MARK: - List Row View

struct ListRowView: View {
    let list: RecordList
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(list.name)
                        .font(.headline)
                    
                    if list.isSystemList {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !list.listDescription.isEmpty {
                    Text(list.listDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Text("\(list.releases.count) \(list.releases.count == 1 ? "album" : "albums")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ListsView()
        .modelContainer(for: [RecordList.self], inMemory: true)
}
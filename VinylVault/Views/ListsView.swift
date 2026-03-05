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
    @Query(sort: \RecordList.orderIndex) private var lists: [RecordList]
    
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
        let list = RecordList(
            name: newListName.trimmingCharacters(in: .whitespaces),
            listDescription: newListDescription.trimmingCharacters(in: .whitespaces),
            orderIndex: lists.count
        )
        
        modelContext.insert(list)
        
        showCreateList = false
        newListName = ""
        newListDescription = ""
    }
    
    private func moveList(from source: IndexSet, to destination: Int) {
        var revisedLists = lists
        revisedLists.move(fromOffsets: source, toOffset: destination)
        
        for (index, list) in revisedLists.enumerated() {
            list.orderIndex = index
        }
    }
    
    private func deleteList(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(lists[index])
        }
    }
}

// MARK: - List Row View

struct ListRowView: View {
    let list: RecordList
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(list.name)
                .font(.headline)
            
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
        .padding(.vertical, 4)
    }
}

#Preview {
    ListsView()
        .modelContainer(for: [RecordList.self], inMemory: true)
}
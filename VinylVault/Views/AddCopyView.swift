// 
//  AddCopyView.swift
//  VinylVault
//
//  Add a new copy of an existing release
//

import SwiftUI
import SwiftData

struct AddCopyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var releases: [Release]
    
    let discogsRelease: DiscogsRelease
    
    @State private var purchasePrice: String = ""
    @State private var condition: String = VinylCondition.nearMint.rawValue
    @State private var notes: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Album")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(discogsRelease.title)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Copy Details") {
                    HStack {
                        Text("Purchase Price")
                        Spacer()
                        TextField("Optional", text: $purchasePrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Condition", selection: $condition) {
                        ForEach(VinylCondition.allCases, id: \.rawValue) { cond in
                            Text(cond.rawValue).tag(cond.rawValue)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $notes)
                            .frame(minHeight: 100)
                    }
                }
            }
            .navigationTitle("Add Copy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addCopy()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func addCopy() {
        guard let release = releases.first(where: { $0.discogsId == discogsRelease.id }) else {
            errorMessage = "Release not found in collection"
            showError = true
            return
        }
        
        let copy = Copy(
            purchasePrice: Double(purchasePrice),
            condition: condition,
            notes: notes
        )
        
        release.copies.append(copy)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to add copy: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    let sampleRelease = DiscogsRelease(
        id: 1,
        title: "Abbey Road",
        year: "1969",
        thumb: nil,
        coverImage: nil,
        resourceUrl: nil,
        format: ["LP"],
        label: ["Apple"],
        genre: ["Rock"],
        style: ["Pop Rock"],
        country: "UK"
    )
    
    AddCopyView(discogsRelease: sampleRelease)
        .modelContainer(for: [Release.self], inMemory: true)
}

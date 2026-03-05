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

    /// Pass the existing Release directly – avoids @Query lookup in nested sheets.
    let release: Release

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
                        Text(release.title)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Artist")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(release.artist)
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
                    .fontWeight(.semibold)
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
    let container = try! ModelContainer(for: Release.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let sampleRelease = Release(
        discogsId: 1,
        title: "Abbey Road",
        artist: "The Beatles",
        year: 1969,
        label: "Apple Records",
        coverImageURL: "",
        thumbnailImageURL: "",
        genres: ["Rock"],
        styles: ["Pop Rock"],
        format: "LP",
        country: "UK",
        barcode: nil,
        tracklist: []
    )
    container.mainContext.insert(sampleRelease)

    return AddCopyView(release: sampleRelease)
        .modelContainer(container)
}
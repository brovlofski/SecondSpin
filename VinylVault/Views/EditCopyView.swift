//
//  EditCopyView.swift
//  VinylVault
//
//  Edit copy details
//

import SwiftUI

struct EditCopyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Bindable var copy: Copy
    
    @State private var purchasePrice: String
    @State private var showDeleteConfirmation = false
    
    init(copy: Copy) {
        self.copy = copy
        _purchasePrice = State(initialValue: copy.purchasePrice.map { String(format: "%.2f", $0) } ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Copy Details") {
                    HStack {
                        Text("Purchase Price")
                        Spacer()
                        TextField("Optional", text: $purchasePrice)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    Picker("Condition", selection: $copy.condition) {
                        ForEach(VinylCondition.allCases, id: \.rawValue) { condition in
                            Text(condition.rawValue).tag(condition.rawValue)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .foregroundColor(.secondary)
                        
                        TextEditor(text: $copy.notes)
                            .frame(minHeight: 100)
                    }
                }
                
                Section {
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete Copy", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Edit Copy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCopy()
                    }
                }
            }
            .confirmationDialog("Delete Copy", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteCopy()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this copy?")
            }
        }
    }
    
    private func saveCopy() {
        copy.purchasePrice = Double(purchasePrice)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save copy: \(error.localizedDescription)")
        }
    }
    
    private func deleteCopy() {
        modelContext.delete(copy)
        dismiss()
    }
}
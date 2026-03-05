//
//  AddRecordView.swift
//  VinylVault
//
//  Add record flow - main view
//

import SwiftUI

struct AddRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showBarcodeScanner = false
    @State private var showManualSearch = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Title
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    
                    Text("Add to Collection")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Choose how you'd like to add a record")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Options
                VStack(spacing: 16) {
                    // Barcode Scan Button
                    Button(action: {
                        showBarcodeScanner = true
                    }) {
                        HStack {
                            Image(systemName: "barcode.viewfinder")
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Scan Barcode")
                                    .font(.headline)
                                
                                Text("Use your camera to scan")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    }
                    .foregroundColor(.primary)
                    
                    // Manual Search Button
                    Button(action: {
                        showManualSearch = true
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Search Manually")
                                    .font(.headline)
                                
                                Text("Enter artist and album title")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    }
                    .foregroundColor(.primary)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showBarcodeScanner) {
                BarcodeScannerView()
            }
            .sheet(isPresented: $showManualSearch) {
                ManualSearchView()
            }
        }
    }
}

#Preview {
    AddRecordView()
}
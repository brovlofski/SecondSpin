//
//  ManualSearchView.swift
//  VinylVault
//
//  Manual search by artist and title
//

import SwiftUI

struct ManualSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ManualSearchViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Search Form
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Artist")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        TextField("Enter artist name", text: $viewModel.artist)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Album Title")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        TextField("Enter album title", text: $viewModel.albumTitle)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Format (Optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., Vinyl, CD, Cassette", text: $viewModel.format)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Country (Optional)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., US, UK, Japan", text: $viewModel.country)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.search)
                            .onSubmit {
                                viewModel.search()
                            }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                
                // Search Button
                Button(action: {
                    viewModel.search()
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "magnifyingglass")
                            Text("Search")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canSearch ? Color.accentColor : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!viewModel.canSearch || viewModel.isLoading)
                
                Spacer()
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Manual Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.showError = false
                }
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $viewModel.showResults) {
                if let results = viewModel.searchResults {
                    SearchResultsView(results: results, searchType: .manual)
                }
            }
        }
    }
}

// MARK: - ViewModel

class ManualSearchViewModel: ObservableObject {
    @Published var artist = ""
    @Published var albumTitle = ""
    @Published var format = ""
    @Published var country = ""
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var showResults = false
    @Published var searchResults: [DiscogsRelease]?
    
    var canSearch: Bool {
        !artist.trimmingCharacters(in: .whitespaces).isEmpty &&
        !albumTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    func search() {
        guard canSearch else { return }
        
        isLoading = true
        
        Task {
            do {
                let trimmedFormat = format.trimmingCharacters(in: .whitespaces)
                let trimmedCountry = country.trimmingCharacters(in: .whitespaces)
                
                let results = try await DiscogsService.shared.searchByArtistAndTitle(
                    artist: artist.trimmingCharacters(in: .whitespaces),
                    title: albumTitle.trimmingCharacters(in: .whitespaces),
                    format: trimmedFormat.isEmpty ? nil : trimmedFormat,
                    country: trimmedCountry.isEmpty ? nil : trimmedCountry
                )
                
                await MainActor.run {
                    isLoading = false
                    searchResults = results
                    showResults = true
                }
            } catch DiscogsError.noResults {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "No results found. Try adjusting your search."
                    showError = true
                }
            } catch DiscogsError.rateLimitExceeded {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Rate limit exceeded. Please try again later."
                    showError = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Search failed: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

#Preview {
    ManualSearchView()
}
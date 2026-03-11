//
//  HomeView.swift
//  VinylVault
//
//  Home screen with Album of the Day
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var releases: [Release]
    
    @State private var albumOfTheDay: Release?
    @State private var wikipediaDescription: String?
    @State private var isLoadingWikipedia = false
    @State private var showFullDescription = false
    @State private var scrollOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
    private let albumOfTheDayKey = "albumOfTheDayKey"
    private let albumOfTheDayDateKey = "albumOfTheDayDateKey"
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // Large Header (shown when at top)
                        if scrollOffset > -50 {
                            largeHeaderView
                                .opacity(max(0, 1 - (abs(scrollOffset) / 50.0)))
                                .offset(y: max(-scrollOffset, 0))
                        }
                        
                        VStack(spacing: 24) {
                            if let album = albumOfTheDay {
                                albumOfTheDayCard(album: album)
                            } else if releases.isEmpty {
                                emptyStateView
                            } else {
                                ProgressView()
                                    .onAppear {
                                        selectAlbumOfTheDay()
                                    }
                            }
                            
                            Spacer()
                        }
                        .padding()
                    }
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: scrollGeometry.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Small header (shown when scrolled)
                    HStack(spacing: 6) {
                        Image("SecondSpinIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("SecondSpin")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .opacity(scrollOffset < -50 ? 1 : 0)
                }
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                selectAlbumOfTheDay()
            }
        }
    }
    
    // MARK: - Large Header View
    
    private var largeHeaderView: some View {
        HStack(spacing: 12) {
            Image("SecondSpinIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48) // 80% of original 60
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            
            Text("SecondSpin")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Album of the Day Card
    
    @ViewBuilder
    private func albumOfTheDayCard(album: Release) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Album of the Day")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text("Swipe to change")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 16) {
                // Album Cover - Changed to square
                CachedAsyncImage(url: URL(string: album.coverImageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                }
                .frame(width: 300, height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                
                // Album Info (simplified - only title and artist)
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(album.artist)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Listen Now Section with Streaming Buttons (no text, no background, aligned left)
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    Text("Listen Now")
                        .font(.headline)
                    
                    HStack(spacing: 24) {
                        Button {
                            StreamingLinkService.shared.openSpotify(
                                release: album,
                                artist: album.artist,
                                album: album.title
                            )
                        } label: {
                            Image("SpotifyIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            StreamingLinkService.shared.openAppleMusic(
                                release: album,
                                artist: album.artist,
                                album: album.title
                            )
                        } label: {
                            Image("AppleMusicIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Wikipedia Description
                if isLoadingWikipedia {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if let description = wikipediaDescription {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                        
                        Text("About")
                            .font(.headline)
                        
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(showFullDescription ? nil : 5)
                        
                        Button(action: {
                            withAnimation {
                                showFullDescription.toggle()
                            }
                        }) {
                            Text(showFullDescription ? "Show Less" : "Read More")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                }
                
                // Action Button - Fixed for dark mode visibility
                NavigationLink(destination: ReleaseDetailView(release: album)) {
                    Text("View Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
        .offset(x: dragOffset)
        .rotationEffect(.degrees(Double(dragOffset) / 20))
        .opacity(isDragging ? 0.8 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    // Only respond to horizontal swipes (horizontal movement > vertical movement)
                    if horizontalAmount > verticalAmount {
                        isDragging = true
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    // Only process if this was a horizontal swipe
                    if horizontalAmount > verticalAmount {
                        let threshold: CGFloat = 100
                        if abs(value.translation.width) > threshold {
                            // Swipe dismissed - animate out and refresh
                            withAnimation(.easeOut(duration: 0.3)) {
                                dragOffset = value.translation.width > 0 ? 500 : -500
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                dragOffset = 0
                                isDragging = false
                                selectAlbumOfTheDay(forceRefresh: true)
                            }
                        } else {
                            // Not enough swipe - bounce back
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragOffset = 0
                                isDragging = false
                            }
                        }
                    } else {
                        // Was a vertical swipe - reset state
                        dragOffset = 0
                        isDragging = false
                    }
                }
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Albums Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add your first vinyl record to see\nyour Album of the Day")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Album of the Day Logic
    
    private func selectAlbumOfTheDay(forceRefresh: Bool = false) {
        guard !releases.isEmpty else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Check if we should use the saved album
        if !forceRefresh,
           let savedDate = UserDefaults.standard.object(forKey: albumOfTheDayDateKey) as? Date,
           let savedId = UserDefaults.standard.object(forKey: albumOfTheDayKey) as? Int,
           calendar.isDate(savedDate, inSameDayAs: today),
           let savedAlbum = releases.first(where: { $0.discogsId == savedId }) {
            // Use saved album
            albumOfTheDay = savedAlbum
            // Only load Wikipedia if we don't have it yet
            if wikipediaDescription == nil {
                loadWikipediaDescription(for: savedAlbum)
            }
        } else {
            // Select new random album - clear previous Wikipedia data
            wikipediaDescription = nil
            if let randomAlbum = releases.randomElement() {
                albumOfTheDay = randomAlbum
                UserDefaults.standard.set(randomAlbum.discogsId, forKey: albumOfTheDayKey)
                UserDefaults.standard.set(today, forKey: albumOfTheDayDateKey)
                loadWikipediaDescription(for: randomAlbum)
            }
        }
    }
    
    private func loadWikipediaDescription(for release: Release) {
        // Skip if already loaded for this release
        guard wikipediaDescription == nil else { return }
        
        isLoadingWikipedia = true
        
        Task {
            do {
                let description = try await WikipediaService.shared.fetchAlbumDescription(
                    albumTitle: release.title,
                    artist: release.artist
                )
                await MainActor.run {
                    wikipediaDescription = description
                    isLoadingWikipedia = false
                }
            } catch {
                await MainActor.run {
                    isLoadingWikipedia = false
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Release.self], inMemory: true)
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
//  ImageGalleryView.swift
//  VinylVault
//
//  Full-screen swipeable image gallery with pinch-to-zoom, double-tap zoom,
//  and swipe up/down to dismiss.
//

import SwiftUI

// MARK: - ImageGalleryView

struct ImageGalleryView: View {
    let imageURLs: [String]
    var initialIndex: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showChrome = true

    // Swipe-to-dismiss state
    @State private var dismissDragOffset: CGFloat = 0
    @State private var isDismissing = false
    // Track zoom level of the current cell so we skip dismiss when zoomed
    @State private var currentCellZoom: CGFloat = 1

    init(imageURLs: [String], initialIndex: Int = 0) {
        self.imageURLs = imageURLs
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            // Paging TabView — offset vertically while being dragged to dismiss
            TabView(selection: $currentIndex) {
                ForEach(imageURLs.indices, id: \.self) { idx in
                    ZoomableImageCell(
                        urlString: imageURLs[idx],
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                        },
                        onScaleChange: { scale in
                            if currentIndex == idx { currentCellZoom = scale }
                        }
                    )
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dismissDragOffset)
            .opacity({
                if isDismissing {
                    return 0
                } else {
                    let offset = abs(dismissDragOffset)
                    return 1 - offset / 400
                }
            }())
            .simultaneousGesture(swipeToDismissGesture)

            // Top chrome: close button + counter
            if showChrome && !isDismissing {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .accessibilityLabel("Close")

                        Spacer()

                        if imageURLs.count > 1 {
                            let current = currentIndex + 1
                            let total = imageURLs.count
                            Text("\(current) / \(total)")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.45))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Spacer()

                    // Dot indicators
                    if imageURLs.count > 1 && imageURLs.count <= 10 {
                        HStack(spacing: 6) {
                            ForEach(imageURLs.indices, id: \.self) { idx in
                                Circle()
                                    .fill(idx == currentIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: idx == currentIndex ? 8 : 6,
                                           height: idx == currentIndex ? 8 : 6)
                                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
                .offset(y: dismissDragOffset)
                .transition(.opacity)
            }
        }
        .statusBar(hidden: !showChrome)
    }

    // MARK: - Swipe to Dismiss Gesture

    private var swipeToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { val in
                guard !isDismissing, currentCellZoom <= 1 else { return }
                // Only respond to predominantly vertical drags
                guard abs(val.translation.height) > abs(val.translation.width) else { return }
                withAnimation(.interactiveSpring()) {
                    dismissDragOffset = val.translation.height
                }
            }
            .onEnded { val in
                guard !isDismissing, currentCellZoom <= 1 else { return }
                guard abs(val.translation.height) > abs(val.translation.width) else {
                    withAnimation(.spring(response: 0.3)) { dismissDragOffset = 0 }
                    return
                }
                let shouldDismiss = abs(val.translation.height) > 80 ||
                                    abs(val.predictedEndTranslation.height) > 300
                if shouldDismiss {
                    isDismissing = true
                    let direction: CGFloat = val.translation.height > 0 ? 1 : -1
                    withAnimation(.easeOut(duration: 0.22)) {
                        dismissDragOffset = direction * 700
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(220))
                        dismiss()
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        dismissDragOffset = 0
                    }
                }
            }
    }
}

// MARK: - ZoomableImageCell

/// Single page: shows one image with pinch zoom + double-tap zoom.
private struct ZoomableImageCell: View {
    let urlString: String
    let onTap: () -> Void
    var onScaleChange: ((CGFloat) -> Void)? = nil

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var loadedImage: UIImage?

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(dragGesture(geo: geo))
                        .gesture(magnificationGesture())
                        .simultaneousGesture(doubleTapGesture(geo: geo))
                        .animation(.interactiveSpring(), value: scale)
                        .animation(.interactiveSpring(), value: offset)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
        .task(id: urlString) {
            await loadImage()
        }
    }

    // MARK: Gestures

    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { val in
                let proposed = lastScale * val
                scale = min(max(proposed, minScale), maxScale)
                onScaleChange?(scale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < minScale {
                    withAnimation(.spring()) { scale = minScale; offset = .zero }
                    lastScale = minScale; lastOffset = .zero
                }
                onScaleChange?(scale)
            }
    }

    private func dragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: scale > 1 ? 1 : 100_000)
            .onChanged { val in
                guard scale > 1 else { return }
                let maxX = (geo.size.width * (scale - 1)) / 2
                let maxY = (geo.size.height * (scale - 1)) / 2
                offset = CGSize(
                    width: clamp(lastOffset.width + val.translation.width, -maxX, maxX),
                    height: clamp(lastOffset.height + val.translation.height, -maxY, maxY)
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func doubleTapGesture(geo: GeometryProxy) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    if scale > 1 {
                        scale = 1; lastScale = 1
                        offset = .zero; lastOffset = .zero
                    } else {
                        scale = 2.5; lastScale = 2.5
                    }
                }
                onScaleChange?(scale)
            }
    }

    private func clamp(_ val: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(val, lo), hi)
    }

    // MARK: Image loading

    @MainActor
    private func loadImage() async {
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }
        if let cached = ImageCache.shared.get(forKey: urlString) {
            loadedImage = cached; return
        }
        let token = "ChNuGIHFtQvJKLkvcQQCEgcdDSVfXvKcVrxQASKO"
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if url.host?.contains("discogs.com") == true {
            req.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
            req.setValue("VinylVault/1.0", forHTTPHeaderField: "User-Agent")
        }
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let img = UIImage(data: data) {
            ImageCache.shared.set(img, forKey: urlString)
            loadedImage = img
        }
    }
}

// MARK: - Preview

#Preview {
    ImageGalleryView(
        imageURLs: [
            "https://picsum.photos/600/600?random=1",
            "https://picsum.photos/600/600?random=2",
            "https://picsum.photos/600/600?random=3"
        ],
        initialIndex: 0
    )
}
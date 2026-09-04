import AVKit
import Kingfisher
import SwiftUI

/// The one full-screen player.
///
/// Horizontal swipe, images and videos treated alike — see docs/adr/0001. The
/// vertical, TikTok-style axis is not here on purpose; it belongs to shuffle,
/// which is a different intent ("browsing" vs "flipping through").
struct ViewerView: View {
    let items: [MediaItem]
    let startIndex: Int
    let client: GalleryClient
    let onClose: () -> Void

    @State private var currentID: String?
    @State private var showsChrome = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        page(for: item)
                            .containerRelativeFrame(.horizontal)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()

            if showsChrome {
                chrome
            }
        }
        .onAppear {
            guard items.indices.contains(startIndex) else { return }
            currentID = items[startIndex].id
        }
        #if os(iOS)
        .statusBarHidden()
        #endif
    }

    @ViewBuilder
    private func page(for item: MediaItem) -> some View {
        if item.isVideo {
            VideoPage(url: client.videoURL(item.path), isActive: currentID == item.id)
        } else {
            ZoomableImage(
                displayURL: client.thumbnailURL(item.path),
                // Only worth the bytes once the user has actually zoomed past
                // what the 1920px tier can show. See docs/adr/0005.
                originalURL: client.originalURL(item.path),
                onSingleTap: { showsChrome.toggle() }
            )
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("viewer-close")

                Spacer()

                if let index = currentIndex {
                    Text("\(index + 1) / \(items.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.4), in: Capsule())
                }
            }
            .padding()

            Spacer()
        }
        .transition(.opacity)
    }

    private var currentIndex: Int? {
        guard let currentID else { return nil }
        return items.firstIndex { $0.id == currentID }
    }
}

/// Pinch/double-tap zoom over a remote image.
private struct ZoomableImage: View {
    let displayURL: URL
    let originalURL: URL
    let onSingleTap: () -> Void

    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    /// Past this much magnification the 1920px tier starts to show, so the
    /// original is worth fetching.
    private var needsOriginal: Bool { scale > 1.8 }

    var body: some View {
        KFImage(needsOriginal ? originalURL : displayURL)
            .placeholder { ProgressView().tint(.white) }
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnification)
            .simultaneousGesture(drag)
            .onTapGesture(count: 2) { toggleZoom() }
            .onTapGesture { onSingleTap() }
            .animation(.interactiveSpring, value: scale)
            .animation(.interactiveSpring, value: offset)
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(steadyScale * value.magnification, 1), 6)
            }
            .onEnded { _ in
                steadyScale = scale
                if scale <= 1.01 { resetPan() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                // Panning only makes sense once the image is larger than the
                // screen; otherwise the horizontal paging gesture owns the drag.
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > 1.01 else { return }
                steadyOffset = offset
            }
    }

    private func toggleZoom() {
        if scale > 1.01 {
            scale = 1
            steadyScale = 1
            resetPan()
        } else {
            scale = 2.5
            steadyScale = 2.5
        }
    }

    private func resetPan() {
        offset = .zero
        steadyOffset = .zero
    }
}

/// A video page. The player is only created for the page actually on screen, so
/// swiping through a wall of videos does not spin up dozens of decoders.
private struct VideoPage: View {
    let url: URL
    let isActive: Bool

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                Color.black
            }
        }
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                let player = player ?? AVPlayer(url: url)
                self.player = player
                player.play()
            } else {
                player?.pause()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

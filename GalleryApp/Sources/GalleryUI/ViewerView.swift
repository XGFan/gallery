import AVKit
import Kingfisher
import SwiftUI

/// The one full-screen player.
///
/// Left/right swipes change media — the only way. A downward drag closes the
/// viewer. There is no vertical paging axis; see docs/adr/0006.
struct ViewerView: View {
    let items: [MediaItem]
    let startIndex: Int
    let client: GalleryClient
    var options: ViewerOptions = .default
    let onClose: () -> Void
    /// Called as the viewer approaches the end of the loaded sequence, so the
    /// folder can page in more rather than dead-ending mid-swipe.
    var onNearEnd: (() -> Void)?
    /// The folder's real total, when it exceeds what has been loaded so far.
    var totalCount: Int?

    @State private var currentID: String?
    @State private var showsChrome = true
    /// Reported up by the page in view; decides whether a drag pans or dismisses.
    @State private var currentScale: CGFloat = 1
    @State private var dismissTranslation: CGSize = .zero
    @State private var autoAdvance: Bool = AutoAdvance.loadEnabled()
    @State private var interval: TimeInterval = AutoAdvance.loadInterval()

    private var dismissProgress: CGFloat {
        ViewerGesture.dismissProgress(translation: dismissTranslation)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - dismissProgress * 0.6)
                .ignoresSafeArea()

            pager
                .scaleEffect(1 - dismissProgress * 0.25)
                .offset(y: max(dismissTranslation.height, 0))

            if showsChrome {
                chrome
            }
        }
        // Attached here rather than inside the image page so a video page can be
        // dismissed the same way.
        .simultaneousGesture(dismissGesture)
        .onAppear {
            guard items.indices.contains(startIndex) else { return }
            currentID = items[startIndex].id
            autoAdvance = options.autoAdvance || AutoAdvance.loadEnabled()
        }
        .onChange(of: currentID) { _, _ in
            currentScale = 1
            requestMoreIfNearEnd()
        }
        .task(id: autoAdvanceTaskID) { await runAutoAdvance() }
        #if os(iOS)
        .statusBarHidden()
        #endif
    }

    private var pager: some View {
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
    }

    @ViewBuilder
    private func page(for item: MediaItem) -> some View {
        if item.isVideo {
            VideoPage(url: client.videoURL(item.path), isActive: currentID == item.id)
                .onTapGesture { showsChrome.toggle() }
        } else {
            ZoomableImage(
                displayURL: client.thumbnailURL(item.path),
                originalURL: client.originalURL(item.path),
                scale: currentID == item.id ? $currentScale : .constant(1),
                onSingleTap: { showsChrome.toggle() }
            )
        }
    }

    /// Only reacts while un-zoomed and only to a clearly downward drag, so a
    /// slightly imperfect horizontal swipe still reaches the pager.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard ViewerGesture.isDismissDrag(translation: value.translation, scale: currentScale)
                else { return }
                // No implicit animation during the drag — it must track the finger.
                dismissTranslation = value.translation
            }
            .onEnded { value in
                let commit = ViewerGesture.shouldCommitDismiss(
                    translation: value.translation,
                    velocity: value.velocity,
                    scale: currentScale
                )
                if commit {
                    onClose()
                } else {
                    withAnimation(.spring(duration: 0.25)) { dismissTranslation = .zero }
                }
            }
    }

    private var chrome: some View {
        VStack {
            HStack(spacing: 12) {
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

                Button {
                    autoAdvance.toggle()
                    AutoAdvance.storeEnabled(autoAdvance)
                } label: {
                    Image(systemName: autoAdvance ? "pause.circle.fill" : "play.circle")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("viewer-autoadvance")

                if autoAdvance {
                    Menu {
                        ForEach(AutoAdvance.intervalChoices, id: \.self) { choice in
                            Button("\(Int(choice)) 秒") {
                                interval = choice
                                AutoAdvance.storeInterval(choice)
                            }
                        }
                    } label: {
                        Text("\(Int(interval))s")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.4), in: Capsule())
                    }
                    .accessibilityIdentifier("viewer-interval")
                }

                Text(counterText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.4), in: Capsule())
            }
            .padding()

            Spacer()
        }
        .transition(.opacity)
    }

    private var counterText: String {
        let position = (currentIndex ?? 0) + 1
        // The folder's real total, not just what happens to be loaded.
        let total = max(totalCount ?? items.count, items.count)
        return "\(position) / \(total)"
    }

    private var currentIndex: Int? {
        guard let currentID else { return nil }
        return items.firstIndex { $0.id == currentID }
    }

    /// Re-created whenever something should restart the timer.
    private var autoAdvanceTaskID: String {
        "\(autoAdvance)-\(interval)-\(currentID ?? "")"
    }

    private func runAutoAdvance() async {
        guard autoAdvance, items.count > 1 else { return }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        guard !Task.isCancelled, autoAdvance else { return }
        guard let index = currentIndex,
              let next = AutoAdvance.nextIndex(current: index, count: items.count)
        else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentID = items[next].id
        }
    }

    private func requestMoreIfNearEnd() {
        guard let onNearEnd, let index = currentIndex else { return }
        if index >= items.count - ViewerView.prefetchMargin { onNearEnd() }
    }

    /// How close to the loaded end triggers another page.
    static let prefetchMargin = 10
}

/// Pinch/double-tap zoom over a remote image.
///
/// Not `private`: the macOS floating window renders the same page.
struct ZoomableImage: View {
    let displayURL: URL
    let originalURL: URL
    @Binding var scale: CGFloat
    let onSingleTap: () -> Void

    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    /// Sticky across the gesture: the tier changes only when the pinch ends, so
    /// hovering around the threshold cannot thrash the URL and flash the
    /// placeholder. See ViewerGesture.originalEnter/ExitScale.
    @State private var usesOriginal = false

    var body: some View {
        KFImage(usesOriginal ? originalURL : displayURL)
            .placeholder { ProgressView().tint(.white) }
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnification)
            // Masked off while un-zoomed. Leaving it live at 1x let it claim
            // horizontal drags and the pager would miss swipes — `.subviews`
            // removes it from recognition entirely rather than letting it
            // recognise and then bail out in the callback (which is too late).
            .simultaneousGesture(pan, including: ViewerGesture.allowsPan(scale: scale) ? .all : .subviews)
            .onTapGesture(count: 2) { toggleZoom() }
            .onTapGesture { onSingleTap() }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // No implicit animation here: animating a continuously updated
                // value is what made the picture judder.
                scale = ViewerGesture.clampScale(steadyScale * value.magnification)
            }
            .onEnded { _ in
                steadyScale = scale
                usesOriginal = ViewerGesture.shouldUseOriginal(
                    scale: scale, currentlyUsingOriginal: usesOriginal
                )
                if !ViewerGesture.isZoomed(scale) {
                    withAnimation(.spring(duration: 0.25)) { resetPan() }
                }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
            }
            .onEnded { _ in steadyOffset = offset }
    }

    private func toggleZoom() {
        let target = ViewerGesture.scaleAfterDoubleTap(current: scale)
        withAnimation(.spring(duration: 0.28)) {
            scale = target
            if !ViewerGesture.isZoomed(target) { resetPan() }
        }
        steadyScale = target
        usesOriginal = ViewerGesture.shouldUseOriginal(
            scale: target, currentlyUsingOriginal: usesOriginal
        )
    }

    private func resetPan() {
        offset = .zero
        steadyOffset = .zero
    }
}

/// A video page. The player is only created for the page actually on screen, so
/// swiping through a wall of videos does not spin up dozens of decoders.
///
/// Not `private`: the macOS floating window renders the same page.
struct VideoPage: View {
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
                release()
            }
        }
        .onDisappear { release() }
    }

    /// Releases the item, not just pauses: a paused AVPlayer on a remote URL
    /// holds its buffer and connection open.
    private func release() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

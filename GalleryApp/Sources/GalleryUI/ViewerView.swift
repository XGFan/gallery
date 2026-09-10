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
    let onClose: () -> Void
    /// Called as the viewer approaches the end of the loaded sequence, so the
    /// folder can page in more rather than dead-ending mid-swipe.
    var onNearEnd: (() -> Void)?
    /// The folder's real total, when it exceeds what has been loaded so far.
    var totalCount: Int?
    /// A `random` stream has no end and no total: the counter drops its
    /// denominator rather than inventing one. See docs/adr/0008.
    var unbounded: Bool = false

    /// The player pages by **position**, not by media identity.
    ///
    /// A `random` stream samples with replacement (docs/adr/0008), so the same
    /// path legitimately shows up more than once — measured at roughly a third
    /// of 30-item batches against the real library. `MediaItem.id` is the path,
    /// so identity-based paging put duplicate ids into `ForEach`, made
    /// `firstIndex(of:)` answer with the *earlier* occurrence, and through that
    /// silently broke the near-the-end check that fetches the next batch.
    /// Positions are unique by construction.
    @State private var currentPosition: Int?
    @State private var showsChrome = true
    /// Reported up by the page in view; decides whether a drag pans or dismisses.
    @State private var currentScale: CGFloat = 1
    @State private var dismissTranslation: CGSize = .zero
    /// True from the first sample of a dismiss drag until the gesture ends *or
    /// is cancelled*. The chrome leaves for the duration: buttons that stay put
    /// while the picture slides out from under them read as a broken screen.
    ///
    /// `@GestureState` rather than `@State` because SwiftUI resets it on
    /// cancellation too — a second finger landing mid-drag cancels the gesture
    /// without ever calling `onEnded`, and a plain flag would stay true and
    /// keep the close button hidden for the life of the presentation.
    @GestureState private var isDragging = false
    /// Set once a dismiss is committed. The picture finishes the trajectory the
    /// finger started — smaller and gone — before the cover is torn down.
    @State private var isClosing = false
    @State private var autoAdvance: Bool = AutoAdvance.loadEnabled()
    @State private var interval: TimeInterval = AutoAdvance.loadInterval()

    /// 0 at rest, 1 when fully dismissed. Tracks the finger during the drag and
    /// runs to the end on commit.
    private var collapse: CGFloat {
        isClosing ? 1 : ViewerGesture.dismissProgress(translation: dismissTranslation)
    }

    var body: some View {
        ZStack {
            // Fades all the way out so the wall shows through — on iOS the
            // cover's own background is cleared for the same reason.
            Color.black
                .opacity(1 - collapse)
                .ignoresSafeArea()

            pager
                .scaleEffect(1 - collapse * 0.25)
                .opacity(isClosing ? 0 : 1)
                .offset(y: max(dismissTranslation.height, 0))

            if showsChrome, !isDragging, !isClosing {
                chrome
            }
        }
        // Attached here rather than inside the image page so a video page can be
        // dismissed the same way.
        .simultaneousGesture(dismissGesture)
        .onAppear {
            guard items.indices.contains(startIndex) else { return }
            currentPosition = startIndex
            autoAdvance = AutoAdvance.loadEnabled()
        }
        .onChange(of: currentPosition) { _, _ in
            currentScale = 1
            requestMoreIfNearEnd()
        }
        .task(id: autoAdvanceTaskID) { await runAutoAdvance() }
        // The gesture-state reset is the only signal a *cancelled* drag gives.
        // Without this the picture would stay shrunken and offset after one.
        .onChange(of: isDragging) { _, dragging in
            guard !dragging, !isClosing, dismissTranslation != .zero else { return }
            withAnimation(.spring(duration: 0.25)) { dismissTranslation = .zero }
        }
        #if os(iOS)
        .statusBarHidden()
        #endif
    }

    private var pager: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    page(for: item, at: index)
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentPosition)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        // On the ScrollView itself, which is a real accessibility element — the
        // same shape as the wall's `masonry-wall`, and unlike a bare container
        // it does not overwrite the identifiers of the pages inside it.
        .accessibilityIdentifier("viewer-pager")
    }

    @ViewBuilder
    private func page(for item: MediaItem, at index: Int) -> some View {
        if item.isVideo {
            VideoPage(url: client.videoURL(item.path), isActive: currentPosition == index)
                .onTapGesture { showsChrome.toggle() }
                // Lets the E2E tell a video page from an image page without
                // knowing anything about the library's contents.
                .accessibilityIdentifier("viewer-video")
        } else {
            ZoomableImage(
                displayURL: client.thumbnailURL(item.path),
                originalURL: client.originalURL(item.path),
                scale: currentPosition == index ? $currentScale : .constant(1),
                onSingleTap: { showsChrome.toggle() }
            )
        }
    }

    /// Only reacts while un-zoomed and only to a clearly downward drag, so a
    /// slightly imperfect horizontal swipe still reaches the pager.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .updating($isDragging) { value, dragging, transaction in
                guard !isClosing,
                      ViewerGesture.isDismissDrag(translation: value.translation, scale: currentScale)
                else { return }
                // Sticky for the rest of the gesture: once a dismiss is in
                // flight the chrome stays away even through a wobbly sample.
                dragging = true
                // Also what the reset animates with when the gesture ends.
                transaction.animation = .easeOut(duration: 0.15)
            }
            .onChanged { value in
                // A drag that starts during the closing animation must not
                // drag a picture that is on its way out.
                guard !isClosing,
                      ViewerGesture.isDismissDrag(translation: value.translation, scale: currentScale)
                else { return }
                // No implicit animation during the drag — it must track the finger.
                dismissTranslation = value.translation
            }
            .onEnded { value in
                // Requiring a dismiss to have been in flight is what stops a
                // curved swipe (right 200pt, then hooking down to 320pt) from
                // paging *and* slamming the viewer shut: every intermediate
                // sample failed the dominance test, so no dismiss ever started.
                guard !isClosing, dismissTranslation != .zero else { return }

                let commit = ViewerGesture.shouldCommitDismiss(
                    translation: value.translation,
                    velocity: value.velocity,
                    scale: currentScale
                )
                if commit {
                    finishDismiss()
                } else {
                    withAnimation(.spring(duration: 0.25)) { dismissTranslation = .zero }
                }
            }
    }

    /// Carry the drag through to the end, then close without the presentation's
    /// own slide: that animation starts from a full-size, opaque player and
    /// contradicts the shrinking one the finger just left.
    private func finishDismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isClosing = true
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { onClose() }
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
                    .accessibilityIdentifier("viewer-counter")
            }
            .padding()

            Spacer()
        }
        .transition(.opacity)
    }

    private var counterText: String {
        let position = (currentIndex ?? 0) + 1
        // An unbounded stream has no denominator to show. Printing the loaded
        // count there would be a lie that shrinks every time a batch lands.
        guard !unbounded else { return "\(position)" }
        // The folder's real total, not just what happens to be loaded.
        let total = max(totalCount ?? items.count, items.count)
        return "\(position) / \(total)"
    }

    private var currentIndex: Int? {
        guard let currentPosition, items.indices.contains(currentPosition) else { return nil }
        return currentPosition
    }

    /// Re-created whenever something should restart the timer.
    private var autoAdvanceTaskID: String {
        "\(autoAdvance)-\(interval)-\(currentPosition ?? -1)"
    }

    private func runAutoAdvance() async {
        guard autoAdvance, items.count > 1 else { return }
        guard let index = currentIndex else { return }
        // A video gets its full duration; a 3s timer would tear a long clip down
        // three seconds in.
        let dwell = AutoAdvance.dwellTime(for: items[index], interval: interval)
        try? await Task.sleep(nanoseconds: UInt64(dwell * 1_000_000_000))
        guard !Task.isCancelled, autoAdvance else { return }
        guard let now = currentIndex,
              let next = AutoAdvance.nextIndex(
                  current: now, count: items.count, wraps: !unbounded
              )
        else { return }
        if next < now {
            // Wrapping to the start: animating would sweep the scroll position
            // across the entire LazyHStack.
            currentPosition = next
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { currentPosition = next }
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
            // The pager keeps adjacent pages alive, so a page revisited after
            // paging away still holds its old steadyScale/offset/usesOriginal.
            // Only `scale` is externalised; syncing the rest off it is what stops
            // the next pinch from jumping straight back to the old magnification.
            .onChange(of: scale) { _, new in
                guard !ViewerGesture.isZoomed(new) else { return }
                steadyScale = 1
                usesOriginal = false
                resetPan()
            }
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
        // Correct regardless of the call site: if a caller reuses this view for
        // a different video without changing its identity, the URL change alone
        // must swap the player. Otherwise the first clip keeps playing.
        .onChange(of: url) { _, newURL in
            release()
            guard isActive else { return }
            let player = AVPlayer(url: newURL)
            self.player = player
            player.play()
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

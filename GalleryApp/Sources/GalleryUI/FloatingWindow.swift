#if os(macOS)
import AppKit
import SwiftUI

/// The desktop-only floating window.
///
/// A borderless small window kept above other windows, cycling media on its own.
/// It is a *window shape*, orthogonal to order and advance (CONTEXT.md): it can
/// show a shuffled or in-order sequence, advancing automatically or by hand.
///
/// This is the one place that needs AppKit: SwiftUI on macOS 14 cannot make a
/// window borderless and floating on its own.
@MainActor
final class FloatingWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: FloatingWindowController?

    static func toggle(client: GalleryClient) {
        if let existing = shared {
            existing.close()
            shared = nil
        } else {
            let controller = FloatingWindowController(client: client)
            controller.showWindow(nil)
            shared = controller
        }
    }

    init(client: GalleryClient) {
        let window = FloatingPanel(
            contentRect: FloatingWindowFrame.load(),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .black
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Programmatically created NSWindows default to releasing themselves on
        // close, which would leave the controller holding a freed window.
        window.isReleasedWhenClosed = false

        super.init(window: window)

        window.delegate = self
        window.contentView = NSHostingView(
            rootView: FloatingContentView(client: client, onClose: { [weak self] in
                self?.closeFloating()
            })
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func closeFloating() {
        close()
        Self.shared = nil
    }

    /// Any close path — Cmd-W, performClose, system teardown — must clear the
    /// singleton, or the next toolbar press "closes" an already-closed window
    /// and appears to do nothing.
    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
    }

    func windowDidMove(_ notification: Notification) { persistFrame() }
    func windowDidResize(_ notification: Notification) { persistFrame() }

    private func persistFrame() {
        guard let frame = window?.frame else { return }
        FloatingWindowFrame.store(frame)
    }
}

/// Size and position survive relaunches — a glance window you have to re-place
/// every time is not a glance window.
enum FloatingWindowFrame {
    private static let key = "floating.frame"
    private static let fallback = NSRect(x: 200, y: 200, width: 420, height: 560)

    static func load() -> NSRect {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return fallback }
        let rect = NSRectFromString(raw)
        guard rect.width > 100, rect.height > 100 else { return fallback }
        // AppKit's automatic frame constraining is skipped for borderless
        // windows, so a frame saved on a display that is now unplugged would
        // restore entirely off-screen — with no title bar to drag it back and no
        // entry in the Window menu.
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) else {
            return fallback
        }
        return rect
    }

    static func store(_ rect: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(rect), forKey: key)
    }
}

/// What the floating window shows: the same page renderers as the full-screen
/// viewer, which is why they are not `private`.
struct FloatingContentView: View {
    let client: GalleryClient
    let onClose: () -> Void

    @State private var items: [MediaItem] = []
    @State private var index = 0
    @State private var scale: CGFloat = 1
    @State private var shuffled = true
    @State private var autoAdvance = true
    @State private var interval: TimeInterval = AutoAdvance.loadInterval()
    @State private var showsControls = false
    @State private var error: GalleryError?
    /// Guards against two concurrent loads finishing out of order — the same
    /// pattern FolderStore uses.
    @State private var loadToken = 0

    private var current: MediaItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black

            if let current {
                // Without an explicit identity two consecutive videos take the
                // same branch at the same position, so SwiftUI reuses the page
                // and its @State player — the first clip just keeps playing.
                page(for: current)
                    .id(current.id)
            } else if let error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ProgressView().tint(.white)
            }

            if showsControls { controls }
        }
        .onHover { showsControls = $0 }
        .task(id: shuffled) { await load() }
        // The id must include the sequence: on first appearance `advance()` runs
        // with an empty `items`, returns immediately, and without `items.count`
        // in the id it would never be restarted once the load lands — leaving the
        // window stuck on the first item forever.
        .task(id: "\(autoAdvance)-\(interval)-\(index)-\(items.count)") { await advance() }
    }

    @ViewBuilder
    private func page(for item: MediaItem) -> some View {
        if item.isVideo {
            VideoPage(url: client.videoURL(item.path), isActive: true)
        } else {
            ZoomableImage(
                displayURL: client.thumbnailURL(item.path),
                originalURL: client.originalURL(item.path),
                scale: $scale,
                onSingleTap: {}
            )
        }
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 8) {
                button("xmark", help: "关闭悬浮窗", action: onClose)
                Spacer()
                button(shuffled ? "shuffle.circle.fill" : "shuffle", help: "随机顺序") {
                    // Reload is driven by .task(id: shuffled), so it is tied to
                    // the view lifecycle and cancelled properly.
                    shuffled.toggle()
                }
                button(autoAdvance ? "pause.fill" : "play.fill", help: "自动前进") {
                    autoAdvance.toggle()
                }
            }
            Spacer()
            HStack(spacing: 8) {
                button("chevron.left", help: "上一张") { step(-1) }
                button("chevron.right", help: "下一张") { step(1) }
            }
        }
        .padding(8)
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        index = ((index + delta) % items.count + items.count) % items.count
        scale = 1
    }

    private func load() async {
        loadToken += 1
        let token = loadToken
        do {
            // A random window into the library rather than always the first
            // page: otherwise the floating window is permanently a slideshow of
            // the same 150 files out of six figures.
            let probe = try await client.mediaPage(path: "", offset: 0, limit: 1)
            let span = max(probe.total - FolderStore.pageSize, 0)
            let offset = span > 0 ? Int.random(in: 0...span) : 0
            let page = try await client.mediaPage(
                path: "", offset: offset, limit: FolderStore.pageSize
            )
            guard token == loadToken else { return }
            let (sequence, _) = MediaOrder.sequence(
                from: page.items,
                entry: nil,
                mixed: MixedModePreference.load(),
                seed: shuffled ? UInt64.random(in: 1...UInt64.max) : nil
            )
            items = sequence
            index = 0
            error = nil
        } catch let galleryError as GalleryError {
            guard token == loadToken else { return }
            error = galleryError
        } catch {
            guard token == loadToken else { return }
            self.error = .badResponse
        }
    }

    private func advance() async {
        guard autoAdvance, items.count > 1 else { return }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        guard !Task.isCancelled, autoAdvance else { return }
        guard let next = AutoAdvance.nextIndex(current: index, count: items.count) else { return }
        index = next
        scale = 1
    }
}

/// A borderless NSWindow refuses key status by default, which makes keyboard
/// shortcuts inert. Overriding it is the only way to grant it.
final class FloatingPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
#endif

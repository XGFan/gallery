import Foundation
import Observation

/// Which way the wall is being scrolled, and whether it sits at the top.
///
/// This is what makes the chrome get out of the way: the top bar and the view
/// switcher show at rest and while scrolling up, and slide away while scrolling
/// down — where the paging counter takes the bottom edge instead. The two are
/// mutually exclusive so they never stack on the same edge.
///
/// **It is fed by which cells are on screen, not by a scroll offset.** The
/// obvious implementation — a `GeometryReader` probe publishing the content's
/// offset through a `PreferenceKey` — was built first and does not work here:
/// the preference fires once at layout and never again while the wall scrolls
/// (verified on iOS 17 — the probe reported 0 through a scroll that moved the
/// content 1000pt). The cells' own `onAppear`/`onDisappear` do fire, reliably,
/// which is already what drives paging. Same signal, one less mechanism.
///
/// The cost is granularity: direction changes a row at a time rather than a
/// point at a time. For showing and hiding chrome that is not a downside — it
/// is jitter-proof by construction, where an offset needs a dead band.
@Observable
@MainActor
final class ScrollIntent {
    enum Direction: Sendable { case up, down, idle }

    /// How long after the last movement the scroll settles back to idle.
    static let idleDelay: Duration = .milliseconds(1500)

    private(set) var direction: Direction = .idle
    private(set) var atTop = true

    /// The chrome is visible at rest and on the way up; on the way down the
    /// wall gets the whole screen.
    var chromeVisible: Bool { atTop || direction == .up }

    /// The paging counter is the bottom edge's other tenant, and only while the
    /// user is actually scrolling down into un-loaded territory.
    var counterVisible: Bool { !atTop && direction == .down }

    private var lastIndex = 0
    private var idleTask: Task<Void, Never>?

    /// `index` is the position, in the wall's own order, of the earliest item
    /// currently on screen.
    func report(firstVisibleIndex index: Int) {
        // A lazy container keeps a render window above the viewport, so item 0
        // stays "visible" a little past the real top. Nothing depends on the
        // boundary being exact — it only decides whether a folder that barely
        // scrolls keeps its chrome, and it should.
        atTop = index == 0

        guard index != lastIndex else { return }
        direction = index > lastIndex ? .down : .up
        lastIndex = index

        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleDelay)
            guard !Task.isCancelled else { return }
            self?.direction = .idle
        }
    }

    /// Called when the wall goes away. Without it a cancelled idle task would
    /// leave the next screen's chrome hidden with nothing to reveal it.
    func reset() {
        idleTask?.cancel()
        idleTask = nil
        direction = .idle
        atTop = true
        lastIndex = 0
    }
}

import SwiftUI

/// Column assignment for the masonry wall.
///
/// Kept as a pure function on purpose: it is the part of the wall that has to be
/// correct (a wrong assignment shows up as wildly uneven columns), and it is the
/// part that stays valid no matter which rendering strategy the wall ends up
/// using — see docs/adr/0002 on switching implementations if SwiftUI can't stay
/// fluid.
enum MasonryLayout {
    /// Assigns each item to the column that is currently shortest, which is what
    /// makes the bottom edge roughly level.
    static func distribute<Item>(
        _ items: [Item],
        columnCount: Int,
        columnWidth: CGFloat,
        aspectRatio: (Item) -> Double
    ) -> [[Item]] {
        guard columnCount > 0 else { return [] }
        var columns: [[Item]] = Array(repeating: [], count: columnCount)
        var heights = [CGFloat](repeating: 0, count: columnCount)

        for item in items {
            var shortest = 0
            for index in heights.indices where heights[index] < heights[shortest] {
                shortest = index
            }
            columns[shortest].append(item)
            // Clamp the ratio so a missing/garbage size can't produce an
            // effectively infinite cell that starves every other column.
            let ratio = min(max(aspectRatio(item), 0.2), 5.0)
            heights[shortest] += columnWidth / ratio
        }
        return columns
    }

    /// Height a cell gets in a column of the given width.
    static func cellHeight(columnWidth: CGFloat, aspectRatio: Double) -> CGFloat {
        columnWidth / min(max(aspectRatio, 0.2), 5.0)
    }

    /// The item to keep under the user's eye across a column-count change.
    ///
    /// Changing the column count re-partitions everything, so scroll offset is
    /// meaningless afterwards — the same offset lands on completely different
    /// content. Anchoring to an *item* is what makes the wall stay put. The
    /// earliest visible item (in the original order, not column order) is used
    /// because it is the one nearest the top of the viewport.
    static func anchorID<Item: Identifiable>(
        items: [Item],
        visible: Set<Item.ID>
    ) -> Item.ID? {
        items.first { visible.contains($0.id) }?.id
    }

    /// How far the computed target must sit from the current count before the
    /// column count actually changes.
    ///
    /// Without this, `round(base / magnification)` has a hard boundary: at base 2
    /// the flip sits at magnification 1.333, and a real finger jitters far more
    /// than the ±0.01 that flips it. Each flip re-partitions the whole wall and
    /// queues another scroll correction, which is felt as judder. Same reasoning
    /// as the image tier's enter/exit gap in ViewerGesture.
    static let columnHysteresis = 0.6

    /// Column count a pinch should produce.
    ///
    /// Spreading the fingers (magnification > 1) means "bigger images", which is
    /// *fewer* columns — hence the division.
    static func columnCount(
        base: Int,
        magnification: CGFloat,
        current: Int,
        min minimum: Int,
        max maximum: Int
    ) -> Int {
        guard magnification > 0 else { return current }
        let raw = Double(base) / Double(magnification)
        guard abs(raw - Double(current)) >= columnHysteresis else { return current }
        return Swift.min(Swift.max(Int(raw.rounded()), minimum), maximum)
    }
}

/// The media wall.
///
/// Deliberately N `LazyVStack`s side by side rather than a custom `Layout`:
/// a `Layout` inside a `ScrollView` instantiates every subview and never
/// recycles, which blows up on a six-figure library. Each column here is
/// independently lazy. See docs/adr/0002 — do not "fix" this into a `Layout`.
struct MasonryWall<Item: Identifiable & Hashable, Cell: View>: View {
    let items: [Item]
    @Binding var columnCount: Int
    let columnRange: ClosedRange<Int>
    let spacing: CGFloat
    let aspectRatio: (Item) -> Double
    let onNearEnd: () -> Void
    /// Fed the scroll offset so the chrome can get out of the way. A
    /// `@MainActor` class rather than a closure on purpose: it is Sendable, so
    /// it can be read from the preference callback without a concurrency
    /// escape hatch.
    let scroll: ScrollIntent
    @ViewBuilder let cell: (Item, CGSize) -> Cell

    /// How many items from the end count as "near the end". One screenful is
    /// roughly enough to fetch the next page before the user reaches the bottom.
    private static var trailingWindow: Int { 24 }

    /// The tail whose appearance asks for another page. Recomputed whenever the
    /// item list grows, which is what re-arms paging for each new page.
    private var trailingIDs: Set<Item.ID> {
        Set(items.suffix(Self.trailingWindow).map(\.id))
    }

    /// Which cells are on screen, so a column-count change can re-anchor to the
    /// topmost one instead of keeping a now-meaningless scroll offset.
    @State private var visibleIDs: Set<Item.ID> = []
    /// Column count when the current pinch began.
    @State private var pinchBaseColumns: Int?
    /// Captured once per pinch. Re-deriving it on every step would let it drift:
    /// `visibleIDs` is fed by LazyVStack's onAppear, whose render window reaches
    /// above the viewport, so the "earliest visible" item creeps upward with
    /// each step. Re-partitioning also fires onAppear/onDisappear for items
    /// moving between columns, and SwiftUI does not order those across siblings.
    @State private var pinchAnchor: Item.ID?
    /// Position of each item in the wall's own order.
    ///
    /// Rebuilt when the item list changes, not consulted by scanning: the scroll
    /// report runs on every cell appearing and disappearing, and a linear search
    /// there is O(items) on the hot path of the one thing ADR-0002 makes a hard
    /// constraint. A dictionary makes it O(visible cells) instead.
    @State private var indexByID: [Item.ID: Int] = [:]

    var body: some View {
        // The width comes from an enclosing GeometryReader, not from a probe in
        // the ScrollView's own background: a background probe measures the
        // *content*, and the content's width is derived from the measurement —
        // a cycle that collapses every column to the 1pt floor and never
        // recovers. Do not "simplify" this into a background probe.
        GeometryReader { proxy in
            let columnWidth = max(
                (proxy.size.width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount),
                1
            )
            let columns = MasonryLayout.distribute(
                items,
                columnCount: columnCount,
                columnWidth: columnWidth,
                aspectRatio: aspectRatio
            )

            ScrollViewReader { scrollProxy in
            ScrollView {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        LazyVStack(spacing: spacing) {
                            ForEach(column) { item in
                                let size = CGSize(
                                    width: columnWidth,
                                    height: MasonryLayout.cellHeight(
                                        columnWidth: columnWidth,
                                        aspectRatio: aspectRatio(item)
                                    )
                                )
                                cell(item, size)
                                    .frame(width: size.width, height: size.height)
                                    // Paging is driven from the cells, not from a
                                    // sentinel below the HStack: a sentinel there is
                                    // not inside a lazy container, so its onAppear
                                    // fires exactly once and paging would stall after
                                    // the second page. These cells are genuinely lazy,
                                    // so each new tail re-arms the trigger.
                                    .id(item.id)
                                    .onAppear {
                                        visibleIDs.insert(item.id)
                                        reportScroll()
                                        if trailingIDs.contains(item.id) { onNearEnd() }
                                    }
                                    .onDisappear {
                                        visibleIDs.remove(item.id)
                                        reportScroll()
                                    }
                            }
                        }
                        .frame(width: columnWidth)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // Simultaneous, not exclusive: UIScrollView's pan has no touch-count
            // limit, so a two-finger pinch with any drift also scrolls. Freezing
            // the scroll for the duration stops the two from fighting.
            .simultaneousGesture(pinch(scrollProxy: scrollProxy))
            .scrollDisabled(pinchBaseColumns != nil)
            .onAppear(perform: rebuildIndex)
            .onChange(of: items.count) { _, _ in rebuildIndex() }
            .onDisappear {
                endPinch()
                scroll.reset()
            }
            }
        }
    }

    /// Tells the chrome which way the wall is moving.
    ///
    /// The earliest on-screen item in the *original* order, not in column order:
    /// with N independently lazy columns there is no single scroll position, but
    /// the earliest visible item advances monotonically as the wall moves, which
    /// is all a direction needs.
    private func reportScroll() {
        guard let index = visibleIDs.compactMap({ indexByID[$0] }).min() else { return }
        scroll.report(firstVisibleIndex: index)
    }

    private func rebuildIndex() {
        // Not `uniqueKeysWithValues`: that traps on a duplicate, and a rescan
        // between pages can genuinely hand the same item back twice (the same
        // reason the paging code trusts the item count over the reported total).
        // A duplicate must cost a slightly stale index, never the process.
        indexByID = Dictionary(
            items.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Pinch to change the column count, keeping the same content under the eye.
    ///
    /// This is the part ADR-0002 singled out as needing care: re-partitioning
    /// invalidates the scroll offset, so the position has to be restored by
    /// item, not by offset.
    private func pinch(scrollProxy: ScrollViewProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchBaseColumns ?? columnCount
                if pinchBaseColumns == nil {
                    pinchBaseColumns = base
                    pinchAnchor = MasonryLayout.anchorID(items: items, visible: visibleIDs)
                }

                let target = MasonryLayout.columnCount(
                    base: base,
                    magnification: value.magnification,
                    current: columnCount,
                    min: columnRange.lowerBound,
                    max: columnRange.upperBound
                )
                guard target != columnCount else { return }

                columnCount = target
                if let anchor = pinchAnchor {
                    // Re-partitioning happens in the same update; scrolling back
                    // to the anchor in the next runloop pass keeps it in view.
                    DispatchQueue.main.async {
                        scrollProxy.scrollTo(anchor, anchor: .top)
                    }
                }
            }
            .onEnded { _ in endPinch() }
    }

    /// Also called from onDisappear: `onEnded` does not fire when SwiftUI
    /// cancels a gesture (incoming call, backgrounding), and a stale base would
    /// make the *next* pinch compute from the wrong starting count.
    private func endPinch() {
        pinchBaseColumns = nil
        pinchAnchor = nil
    }
}

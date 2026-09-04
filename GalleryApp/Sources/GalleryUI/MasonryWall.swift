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

    /// Column count a pinch should produce.
    ///
    /// Spreading the fingers (magnification > 1) means "bigger images", which is
    /// *fewer* columns — hence the division.
    static func columnCount(
        base: Int,
        magnification: CGFloat,
        min minimum: Int,
        max maximum: Int
    ) -> Int {
        guard magnification > 0 else { return base }
        let target = (Double(base) / magnification).rounded()
        return Swift.min(Swift.max(Int(target), minimum), maximum)
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
                                        if trailingIDs.contains(item.id) { onNearEnd() }
                                    }
                                    .onDisappear { visibleIDs.remove(item.id) }
                            }
                        }
                        .frame(width: columnWidth)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .gesture(pinch(scrollProxy: scrollProxy))
            }
        }
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
                if pinchBaseColumns == nil { pinchBaseColumns = base }

                let target = MasonryLayout.columnCount(
                    base: base,
                    magnification: value.magnification,
                    min: columnRange.lowerBound,
                    max: columnRange.upperBound
                )
                guard target != columnCount else { return }

                let anchor = MasonryLayout.anchorID(items: items, visible: visibleIDs)
                columnCount = target
                if let anchor {
                    // Re-partitioning happens in the same update; scrolling back
                    // to the anchor in the next runloop pass keeps it in view.
                    DispatchQueue.main.async {
                        scrollProxy.scrollTo(anchor, anchor: .top)
                    }
                }
            }
            .onEnded { _ in pinchBaseColumns = nil }
    }
}

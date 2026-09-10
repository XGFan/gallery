import SwiftUI

/// The folder tree behind the drawer / sidebar.
///
/// Two separate hit targets per row, which is the whole point (docs/adr/0007):
/// the triangle only opens and closes, the rest of the row only navigates.
/// `List(children:)` cannot express that — it folds expansion into the row's own
/// tap, so opening a branch to look inside also drags the whole screen to it,
/// and reaching a deep folder means navigating through every level on the way.
/// Hence a hand-rolled `LazyVStack` instead.
///
/// Pure presentation: expansion state lives in `TreeStore`, selection comes from
/// the route.
struct FolderTreeView: View {
    /// The root's children — the root itself is not drawn as a row.
    let nodes: [FolderTree.Node]
    let selectedPath: String
    let isExpanded: (String) -> Bool
    /// Triangle only: open or close, never navigate.
    let onToggle: (String) -> Void
    /// Row only: navigate, never change expansion.
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(visibleNodes) { item in
                    row(item)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        // No container-level identifier here. SwiftUI pushes an identifier on a
        // non-element container down onto its leaves, overwriting the ones the
        // buttons set for themselves — every control inside came back named
        // after the container and no test could find any of them. Same trap as
        // the note on WallCell's identifier in FolderView.
    }

    /// One row's worth of indentation.
    private static let indent: CGFloat = 14
    /// Also the row height. The triangle has to be a thumb's worth on iOS or it
    /// is simply not hittable next to a full-width row target — this is the one
    /// fragile part of the two-target design, so the region is sized explicitly
    /// rather than left to whatever the glyph happens to measure. macOS inherits
    /// the same generous region, where it costs nothing.
    private static let hitSize: CGFloat = 44

    private struct VisibleNode: Identifiable {
        let node: FolderTree.Node
        let depth: Int
        var id: String { node.path }
    }

    /// The tree flattened to the rows that are actually on screen.
    ///
    /// Recursing in the view hierarchy instead would nest a container per level
    /// and build every descendant of an open branch eagerly, which defeats the
    /// `LazyVStack` — the drawer opens onto a library thousands of folders deep.
    /// Flattening keeps one lazy list no matter how deep the expansion goes.
    private var visibleNodes: [VisibleNode] {
        var result: [VisibleNode] = []
        func walk(_ list: [FolderTree.Node], depth: Int) {
            for node in list {
                result.append(VisibleNode(node: node, depth: depth))
                if isExpanded(node.path) {
                    walk(node.children, depth: depth + 1)
                }
            }
        }
        walk(nodes, depth: 0)
        return result
    }

    private func row(_ item: VisibleNode) -> some View {
        let node = item.node
        let isSelected = node.path == selectedPath

        return HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(item.depth) * Self.indent, height: 1)

            disclosure(node)

            Button {
                onSelect(node.path)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Text(node.name)
                        .font(.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, minHeight: Self.hitSize, alignment: .leading)
                // The label is mostly empty space to the right of the name; the
                // whole strip has to accept the tap, not just the glyphs.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // On the button, not inside its label: a Button absorbs the
            // accessibility of its content and would hide an inner identifier.
            .accessibilityIdentifier("tree-node:\(node.path)")
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
            }
        }
    }

    @ViewBuilder
    private func disclosure(_ node: FolderTree.Node) -> some View {
        if node.isLeaf {
            // A leaf draws no triangle but still reserves its width, otherwise
            // names at the same depth would not line up with each other.
            Color.clear.frame(width: Self.hitSize, height: Self.hitSize)
        } else {
            let expanded = isExpanded(node.path)
            Button {
                onToggle(node.path)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: Self.hitSize, height: Self.hitSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: expanded)
            .accessibilityIdentifier("tree-disclosure:\(node.path)")
        }
    }
}

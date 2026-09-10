import SwiftUI

/// The folder navigator behind the drawer / sidebar: one level at a time.
///
/// Not a tree. A header names the level; below it are that level's subfolders,
/// each with the full width of the panel. See docs/adr/0010 for why the
/// expandable tree went away.
///
/// Two hit targets per branch row, deliberately assigned against the iOS
/// convention that a trailing `›` means "the whole row opens": the *name*
/// navigates to the folder, the `›` drills the sidebar into it without moving
/// the wall. "Everything under Twitter" is one tap that way. The header's name
/// navigates to the level itself and its `‹` goes back up.
///
/// Pure presentation apart from one piece of local state: which level is
/// showing. It follows the current folder — after any navigation the level is
/// the current folder's parent, so the folder is highlighted among its siblings
/// — and stays wherever the user drilled to until the next navigation.
struct FolderTreeView: View {
    let selectedPath: String
    /// One level's worth of subfolders.
    let childrenOf: (String) -> [FolderTree.Node]
    /// Navigate. The only way out of the sidebar.
    let onSelect: (String) -> Void

    @State private var levelPath = ""
    /// Which way the next level change slides.
    @State private var drillingDown = true

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(childrenOf(levelPath)) { node in
                        row(node)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            // A new identity per level is what makes the slide a slide: the
            // old list leaves as the new one enters, instead of rows morphing.
            .id(levelPath)
            .transition(.asymmetric(
                insertion: .move(edge: drillingDown ? .trailing : .leading),
                removal: .move(edge: drillingDown ? .leading : .trailing)
            ))
        }
        .clipped()
        .onChange(of: selectedPath, initial: true) { _, path in
            levelPath = TreeStore.parentPath(of: path)
        }
        // No container-level identifier here. SwiftUI pushes an identifier on a
        // non-element container down onto its leaves, overwriting the ones the
        // buttons set for themselves — every control inside came back named
        // after the container and no test could find any of them. Same trap as
        // the note on WallCell's identifier in FolderView.
    }

    private static let rowHeight: CGFloat = 44

    private var levelName: String {
        levelPath.isEmpty ? "图库" : String(levelPath.split(separator: "/").last ?? "")
    }

    private func show(level path: String, down: Bool) {
        drillingDown = down
        withAnimation(.easeOut(duration: 0.25)) { levelPath = path }
    }

    // MARK: - Header

    private var header: some View {
        let isSelected = levelPath == selectedPath
        return HStack(spacing: 4) {
            if !levelPath.isEmpty {
                Button {
                    show(level: TreeStore.parentPath(of: levelPath), down: false)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tree-back")
            }

            Button {
                onSelect(levelPath)
            } label: {
                HStack(spacing: 8) {
                    if levelPath.isEmpty {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 14, weight: .semibold))
                            // Decorative: the header's accessible name is the
                            // level's name alone.
                            .accessibilityHidden(true)
                    }
                    Text(levelName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .padding(.horizontal, levelPath.isEmpty ? 12 : 4)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // On the button, not inside its label: a Button absorbs the
            // accessibility of its content and would hide an inner identifier.
            .accessibilityIdentifier("tree-level")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
        }
    }

    // MARK: - Rows

    private func row(_ node: FolderTree.Node) -> some View {
        let isSelected = node.path == selectedPath
        return HStack(spacing: 0) {
            Button {
                onSelect(node.path)
            } label: {
                Text(node.name)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    // A folder's distinguishing part is usually its tail.
                    .truncationMode(.middle)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                    // The label is mostly empty space to the right of the name;
                    // the whole strip has to accept the tap, not just the glyphs.
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tree-node:\(node.path)")

            if !node.isLeaf {
                Button {
                    show(level: node.path, down: true)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        // Not `.secondary`: over the drawer's material that
                        // style goes vibrant and vanishes against a dark wall.
                        // The old tree's triangles were invisible for exactly
                        // this reason (docs/adr/0010).
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .frame(width: 44, height: Self.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tree-disclosure:\(node.path)")
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5).padding(.leading, 12)
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
    }
}

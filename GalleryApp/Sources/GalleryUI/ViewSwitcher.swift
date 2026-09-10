import SwiftUI

/// The view switcher: `explore` / `album` / `image`.
///
/// Pure presentation — which cells to show, which one is current, and what
/// happens on a tap all come from the caller. It draws itself as a floating
/// capsule and takes no layout space, so the caller hangs it off the wall with
/// `.overlay(alignment: .bottom)`.
///
/// `random` is not in here. It is an action, not a view (CONTEXT.md), and it
/// has its own button — `RandomButton`. The caller does not show the switcher
/// at all when it would have a single cell: a strip with one option is not a
/// switch.
struct ViewSwitcher: View {
    /// Which view cells to show, in display order. A leaf folder passes fewer
    /// (docs/adr/0007).
    let views: [FolderViewKind]
    let current: FolderViewKind
    let isVisible: Bool
    let onSelect: (FolderViewKind) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(views, id: \.self) { kind in
                cell(
                    icon: Self.icon(for: kind),
                    label: Self.label(for: kind),
                    identifier: "view-switcher:\(kind.rawValue)",
                    isSelected: kind == current
                ) {
                    onSelect(kind)
                }
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        // The material follows the color scheme, and in light mode it would
        // render pale — under white glyphs on top of a photo wall that is
        // unreadable. Pinning the chrome to dark keeps one look on both
        // platforms and both schemes, and lets the foregrounds stay white.
        .environment(\.colorScheme, .dark)
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .padding(.bottom, 12)
        .offset(y: isVisible ? 0 : Self.hiddenOffset)
        .opacity(isVisible ? 1 : 0)
        // Opacity alone still leaves a fully tappable strip across the bottom of
        // the wall, so taps meant for a cell would land on an invisible switcher.
        .allowsHitTesting(isVisible)
        // And out of the accessibility tree with it, so VoiceOver does not
        // announce controls that are not on screen. (XCUITest still reports
        // them as existing, so tests assert on position instead.)
        .accessibilityHidden(!isVisible)
        .animation(.easeOut(duration: 0.3), value: isVisible)
        // No container-level identifier here. SwiftUI pushes an identifier on a
        // non-element container down onto its leaves, overwriting the ones the
        // buttons set for themselves — every control inside came back named
        // after the container and no test could find any of them. Same trap as
        // the note on WallCell's identifier in FolderView.
    }

    /// Far enough to clear the capsule and the home indicator underneath it.
    private static let hiddenOffset: CGFloat = 120

    /// Icon over label, the way the Photos segmented control does it. Side by
    /// side, three cells with words in them do not fit across a 375pt screen
    /// next to the random button without truncating.
    private func cell(
        icon: String,
        label: String,
        identifier: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.6))
            .frame(minWidth: 58)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule().fill(.white.opacity(0.14))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // On the button, not inside its label: a Button absorbs the
        // accessibility of its content and would hide an inner identifier.
        .accessibilityIdentifier(identifier)
    }

    /// The labels are the web frontend's own words. One vocabulary across both
    /// frontends — deliberately not translated (CONTEXT.md).
    private static func label(for kind: FolderViewKind) -> String {
        switch kind {
        case .explore: "Explore"
        case .album: "Album"
        case .image: "Image"
        }
    }

    private static func icon(for kind: FolderViewKind) -> String {
        switch kind {
        case .explore: "folder"
        case .album: "rectangle.stack"
        case .image: "photo.on.rectangle.angled"
        }
    }
}

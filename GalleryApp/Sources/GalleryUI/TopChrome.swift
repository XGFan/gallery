import SwiftUI

/// One level of the current path, root first.
struct PathCrumb: Identifiable, Hashable {
    /// The root's own name is the caller's to choose ("图库"); everything else
    /// is the folder's name.
    let name: String
    /// Empty string for the root — the same path shape the API takes.
    let path: String

    var id: String { path }

    var isRoot: Bool { path.isEmpty }
}

/// The floating top bar: drawer, back, and the current folder's name.
///
/// Mirror image of `ViewSwitcher` — same glass, same hide-on-scroll behaviour,
/// leaving out of the top instead of the bottom. Pure presentation apart from
/// one piece of local state: whether the ancestor sheet is up.
struct TopChrome: View {
    let title: String
    /// Root to current, current last. Also what the ancestor sheet lists.
    let crumbs: [PathCrumb]
    let isVisible: Bool
    let showsBack: Bool
    let onDrawer: () -> Void
    let onBack: () -> Void
    /// Receives `crumb.path`.
    let onJump: (String) -> Void

    @State private var showsPathSheet = false

    var body: some View {
        bar
            .padding(.top, 12)
            .padding(.horizontal, 16)
            .offset(y: isVisible ? 0 : -Self.hiddenOffset)
            .opacity(isVisible ? 1 : 0)
            // Without this the hidden bar still swallows taps aimed at the top
            // row of the wall.
            .allowsHitTesting(isVisible)
            // And out of the accessibility tree with it, so VoiceOver does not
            // announce controls that are not on screen. (XCUITest still reports
            // them as existing, so tests assert on position instead.)
            .accessibilityHidden(!isVisible)
            .animation(.easeOut(duration: 0.3), value: isVisible)
            // No container-level identifier here: SwiftUI pushes an identifier
            // on a non-element container down onto its leaves, overwriting the
            // ones the buttons set for themselves. Every control inside came
            // back named after the container and no test could find any of
            // them. Same trap as the note on WallCell's identifier.
            // Presented from out here, above the bar's forced-dark environment:
            // a sheet inherits the environment of whatever presents it, and the
            // sheet is ordinary content that should follow the user's scheme.
            .sheet(isPresented: $showsPathSheet) {
                PathSheet(
                    crumbs: crumbs,
                    onSelect: { path in
                        showsPathSheet = false
                        onJump(path)
                    },
                    onClose: { showsPathSheet = false }
                )
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
            }
    }

    private static let hiddenOffset: CGFloat = 120

    private var bar: some View {
        HStack(spacing: 2) {
            iconButton("line.3.horizontal", identifier: "top-drawer-button", action: onDrawer)

            if showsBack {
                iconButton("chevron.left", identifier: "top-back-button", action: onBack)
            }

            titleButton
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        // Same reason as ViewSwitcher: pin the chrome to dark so white glyphs
        // stay readable over a photo wall in either color scheme.
        .environment(\.colorScheme, .dark)
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
    }

    private func iconButton(
        _ systemName: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                // 44pt so the target is a thumb's worth on iOS; the glyph itself
                // is far smaller than the region that accepts the tap.
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var titleButton: some View {
        Button {
            showsPathSheet = true
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    // A deep folder's distinguishing part is usually its tail,
                    // so eat the middle rather than the end.
                    .truncationMode(.middle)
                // Nearly invisible on purpose: it only has to hint that the
                // title is a control, not compete with the title.
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .frame(maxWidth: 220)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("top-title-button")
    }
}

/// The ancestry as a vertical, indented list.
///
/// Same trade as the web frontend's `PathSheet.tsx`: a horizontal breadcrumb
/// runs off the side of a phone once the path is a few levels deep, and one
/// that scrolls horizontally is a thing nobody finds. Indented rows scroll the
/// way everything else does, and every level is one tap away.
struct PathSheet: View {
    let crumbs: [PathCrumb]
    let onSelect: (String) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                        row(crumb, depth: index, isCurrent: index == crumbs.count - 1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        // Same trap as above: an identifier here would rename every crumb and
        // the done button after the sheet. The crumbs are the sheet's proof of
        // existence anyway.
        #if os(macOS)
        // A macOS sheet has no detents and no intrinsic size to fall back on.
        .frame(minWidth: 320, minHeight: 360)
        #endif
    }

    private var header: some View {
        HStack {
            Text("路径")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button("完成", action: onClose)
                .font(.callout)
                .accessibilityIdentifier("path-sheet-close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func row(_ crumb: PathCrumb, depth: Int, isCurrent: Bool) -> some View {
        Button {
            onSelect(crumb.path)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: crumb.isRoot ? "house" : "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                Text(crumb.name)
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, CGFloat(depth) * 16 + 12)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The current folder is where the user already is: showing it keeps the
        // ancestry complete, but tapping it would be a no-op navigation.
        .disabled(isCurrent)
        .accessibilityIdentifier("path-crumb:\(crumb.path)")
    }
}

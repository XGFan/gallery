import SwiftUI

/// The floating top bar: drawer, back, and the current folder's name.
///
/// Mirror image of `ViewSwitcher` — same glass, same hide-on-scroll behaviour,
/// leaving out of the top instead of the bottom. Pure presentation.
///
/// It hugs its content and sits in the leading corner, so what it covers of the
/// wall is one corner rather than a band across the first row. The title is
/// just a label: the way up and across is the sidebar (docs/adr/0010).
struct TopChrome: View {
    let title: String
    let isVisible: Bool
    let showsBack: Bool
    let onDrawer: () -> Void
    let onBack: () -> Void

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
    }

    private static let hiddenOffset: CGFloat = 120

    private var bar: some View {
        HStack(spacing: 0) {
            iconButton("line.3.horizontal", identifier: "top-drawer-button", action: onDrawer)

            if showsBack {
                iconButton("chevron.left", identifier: "top-back-button", action: onBack)
            }

            titleLabel
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

    private var titleLabel: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            // A deep folder's distinguishing part is usually its tail, so eat
            // the middle rather than the end.
            .truncationMode(.middle)
            // Shrink to the text, capped. A bare `frame(maxWidth:)` is not "at
            // most 220" — it takes the whole 220 whenever it is offered, which
            // is always, and that is what stretched "图库" into a 290pt bar.
            .frame(maxWidth: 220)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, showsBack ? 2 : 6)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .accessibilityIdentifier("top-title")
    }
}

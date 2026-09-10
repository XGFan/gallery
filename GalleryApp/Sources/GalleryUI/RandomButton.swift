import SwiftUI

/// The `random` action's button: floats in the bottom-trailing corner of the
/// wall, on its own.
///
/// It is not a cell of the switcher because it is not a view — pressing it
/// samples and enters the player, and nothing stays selected (CONTEXT.md,
/// docs/adr/0008). Keeping it apart is also what lets the switcher disappear
/// entirely in a leaf folder, where `random` still makes sense.
///
/// Same glass and the same hide-on-scroll rule as the rest of the chrome: the
/// wall is the product, and a button that never moved would sit on the corner
/// cell for good.
struct RandomButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "shuffle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Circle())
        .environment(\.colorScheme, .dark)
        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .offset(y: isVisible ? 0 : Self.hiddenOffset)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(.easeOut(duration: 0.3), value: isVisible)
        .accessibilityIdentifier("random-button")
    }

    private static let hiddenOffset: CGFloat = 120
}

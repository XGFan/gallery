import SwiftUI

@main
struct GalleryAppMain: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // A photo wall reads best against dark chrome, and it keeps the
                // viewer's black background from being a jarring transition.
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 750)
        .commands { WallCommands() }
        #endif
    }
}

#if os(macOS)
/// Column-count commands in the menu bar.
///
/// The toolbar is gone (docs/adr/0007) and with it the ± buttons, so pinching is
/// the primary way to change the column count. That leaves a hole for anyone on
/// a mouse: `MagnifyGesture` only ever sees a trackpad. The menu bar is what
/// fills it — a discoverable home for the shortcuts, costing no screen space.
/// The other half of the fix is ⌘ + scroll wheel, installed in `RootView`.
struct WallCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("放大") { WallColumns.shared.zoom(1) }
                .keyboardShortcut("+", modifiers: .command)
            // The physical key is "=", and that is what most people actually
            // press for "zoom in". Bound as well so ⌘= works without shift.
            Button("放大") { WallColumns.shared.zoom(1) }
                .keyboardShortcut("=", modifiers: .command)
                .hidden()
            Button("缩小") { WallColumns.shared.zoom(-1) }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
        }
    }
}
#endif

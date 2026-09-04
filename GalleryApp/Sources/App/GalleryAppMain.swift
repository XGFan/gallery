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
        #endif
    }
}

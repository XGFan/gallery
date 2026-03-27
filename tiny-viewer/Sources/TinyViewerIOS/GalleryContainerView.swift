import SwiftUI
import TinyViewerCore

public struct GalleryContainerView: View {
    @StateObject private var viewModel: GalleryViewModel
    
    public init(category: String = "") {
        let config = ImageGalleryConfig(category: category)
        _viewModel = StateObject(wrappedValue: GalleryViewModel(config: config))
    }
    
    public var body: some View {
        GalleryPageView(viewModel: viewModel)
            .task {
                await viewModel.loadImages()
            }
            #if os(iOS)
            .statusBarHidden(true)
            .modifier(HideSystemOverlaysModifier())
            #endif
    }
}

struct HideSystemOverlaysModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            content.persistentSystemOverlays(.hidden)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

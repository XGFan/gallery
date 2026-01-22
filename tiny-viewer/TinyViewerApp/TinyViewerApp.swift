import SwiftUI
import TinyViewerIOS
import TinyViewerCore

@main
struct TinyViewerAppMain: App {
    @State private var category: String = ""
    @State private var refreshID = UUID()
    
    var body: some Scene {
        WindowGroup {
            GalleryContainerView(category: category)
                .id(refreshID)
                .onOpenURL { url in
                    let newCategory = parseCategory(from: url)
                    if newCategory != category {
                        category = newCategory
                        refreshID = UUID()
                    }
                }
        }
    }
    
    private func parseCategory(from url: URL) -> String {
        var parts: [String] = []
        
        if let host = url.host, !host.isEmpty {
            parts.append(host)
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        parts.append(contentsOf: pathComponents)
        
        if !parts.isEmpty {
            return parts.joined(separator: "/")
        }
        
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let categoryParam = components.queryItems?.first(where: { $0.name == "category" })?.value {
            return categoryParam
        }
        
        return ""
    }
}

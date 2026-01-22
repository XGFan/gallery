import SwiftUI
import Kingfisher
import TinyViewerCore

@MainActor
public class GalleryViewModel: ObservableObject {
    @Published public var images: [ImageNode] = []
    @Published public var currentIndex: Int = 0
    @Published public var isLoading: Bool = false
    @Published public var error: Error?
    
    public let config: ImageGalleryConfig
    private var prefetcher: ImagePrefetcher?
    
    public var currentImage: ImageNode? {
        guard !images.isEmpty, currentIndex >= 0, currentIndex < images.count else { return nil }
        return images[currentIndex]
    }
    
    public init(config: ImageGalleryConfig) {
        self.config = config
    }
    
    public func loadImages() async {
        isLoading = true
        error = nil
        
        do {
            images = try await NetworkManager.shared.fetchImages(config: config)
            currentIndex = 0
            prefetchNearbyImages()
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    public func nextImage() {
        guard !images.isEmpty else { return }
        currentIndex = (currentIndex + 1) % images.count
    }
    
    public func previousImage() {
        guard !images.isEmpty else { return }
        currentIndex = (currentIndex - 1 + images.count) % images.count
    }
    
    public func prefetchNearbyImages() {
        guard !images.isEmpty else { return }
        
        prefetcher?.stop()
        
        var urlsToPrefetch: [URL] = []
        let range = -3...3
        
        for offset in range {
            let index = (currentIndex + offset + images.count) % images.count
            if index != currentIndex {
                if let url = config.imageURL(for: images[index]) {
                    urlsToPrefetch.append(url)
                }
            }
        }
        
        prefetcher = ImagePrefetcher(urls: urlsToPrefetch)
        prefetcher?.start()
    }
}

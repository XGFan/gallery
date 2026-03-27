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

    var imageFetcher: @Sendable (ImageGalleryConfig) async throws -> [ImageNode] = { config in
        try await NetworkManager.shared.fetchImages(config: config)
    }
    
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
            images = try await imageFetcher(config)
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
        let urlsToPrefetch = nearbyImageURLsForPrefetch()
        prefetcher = ImagePrefetcher(urls: urlsToPrefetch)
        prefetcher?.start()
    }

    func nearbyImageURLsForPrefetch() -> [URL] {
        guard !images.isEmpty else { return [] }

        var urlsToPrefetch: [URL] = []
        let range = -3...3

        for offset in range {
            let index = (currentIndex + offset + images.count) % images.count
            if index != currentIndex, let url = config.imageURL(for: images[index]) {
                urlsToPrefetch.append(url)
            }
        }

        return urlsToPrefetch
    }
}

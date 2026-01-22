import SwiftUI
import Kingfisher
import TinyViewerCore

public struct GalleryContentView: View {
    @ObservedObject var viewModel: GalleryViewModel
    let onImageSizeChanged: @MainActor @Sendable (CGSize) -> Void
    
    public init(viewModel: GalleryViewModel, onImageSizeChanged: @escaping @MainActor @Sendable (CGSize) -> Void) {
        self.viewModel = viewModel
        self.onImageSizeChanged = onImageSizeChanged
    }
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let currentImage = viewModel.currentImage,
                   let imageURL = viewModel.config.imageURL(for: currentImage) {
                    KFImage(imageURL)
                        .onSuccess { result in
                            Task { @MainActor in
                                onImageSizeChanged(result.image.size)
                            }
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(2)
                        .frame(width: 100, height: 100)
                } else {
                    Text("No images")
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            if viewModel.isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(8)
            }
        }
        .background(Color.black)
        .onChangeCompat(of: viewModel.currentIndex) {
            viewModel.prefetchNearbyImages()
        }
    }
}

@MainActor
public class GalleryViewModel: ObservableObject {
    @Published public var images: [ImageNode] = []
    @Published public var currentIndex: Int = 0
    @Published public var isLoading: Bool = false
    @Published public var error: Error?
    @Published public var isPlaying: Bool = false
    
    public let config: ImageGalleryConfig
    private var prefetcher: ImagePrefetcher?
    private var slideshowTimer: Timer?
    private let slideshowInterval: TimeInterval = 3.0
    
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
    
    public func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            startSlideshow()
        } else {
            stopSlideshow()
        }
    }
    
    private func startSlideshow() {
        stopSlideshow()
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: slideshowInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.nextImage()
            }
        }
    }
    
    private func stopSlideshow() {
        slideshowTimer?.invalidate()
        slideshowTimer = nil
    }
}

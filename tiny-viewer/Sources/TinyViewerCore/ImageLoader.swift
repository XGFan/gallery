import Foundation
import Kingfisher

public class ImageLoader {
    public init() {}
    
    public func configureKingfisher() {
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 500 * 1024 * 1024
    }
}

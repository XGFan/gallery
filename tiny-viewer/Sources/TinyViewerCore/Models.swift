import Foundation

public struct ImageGalleryConfig: Sendable {
    public let baseURL: String
    public let category: String
    
    public init(baseURL: String = "https://gallery.test4x.com", category: String = "") {
        self.baseURL = baseURL
        self.category = category
    }
    
    public var apiEndpoint: URL? {
        let path = category.isEmpty ? "" : "/\(category)"
        return URL(string: "\(baseURL)/api/image\(path)")
    }
    
    /// Returns the image URL for a given node.
    /// Supports both raw paths (e.g., "Weibo/kyokyo不是qq啊") and 
    /// already percent-encoded paths (e.g., "Weibo/kyokyo%E4%B8%8D%E6%98%AFqq%E5%95%8A").
    public func imageURL(for node: ImageNode) -> URL? {
        let finalPath: String
        
        // If removingPercentEncoding changes the string, it was already encoded
        if let decoded = node.path.removingPercentEncoding, decoded != node.path {
            // Already percent-encoded, use as-is
            finalPath = node.path
        } else {
            // Raw string, needs encoding
            finalPath = node.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node.path
        }
        
        return URL(string: "\(baseURL)/file/\(finalPath)")
    }
}

public struct ImageNode: Codable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let width: Int?
    public let height: Int?
    
    public init(name: String, path: String, width: Int? = nil, height: Int? = nil) {
        self.name = name
        self.path = path
        self.width = width
        self.height = height
    }
    
    public var aspectRatio: CGFloat {
        guard let w = width, let h = height, h > 0 else { return 1.0 }
        return CGFloat(w) / CGFloat(h)
    }
}

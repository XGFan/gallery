import Foundation

public final class NetworkManager: Sendable {
    public static let shared = NetworkManager()
    
    private init() {}
    
    public func fetchImages(config: ImageGalleryConfig) async throws -> [ImageNode] {
        guard let endpoint = config.apiEndpoint else {
            throw NetworkError.invalidResponse
        }
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }
        
        var images = try JSONDecoder().decode([ImageNode].self, from: data)
        images.shuffle()
        return images
    }
}

public enum NetworkError: Error, LocalizedError {
    case invalidResponse
    case emptyImageList
    case decodingFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .emptyImageList:
            return "No images found"
        case .decodingFailed:
            return "Failed to decode image list"
        }
    }
}

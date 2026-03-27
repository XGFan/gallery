import Foundation

public final class NetworkManager: Sendable {
    public static let shared = NetworkManager()
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    public func fetchImages(config: ImageGalleryConfig) async throws -> [ImageNode] {
        guard let endpoint = config.apiEndpoint else {
            throw NetworkError.invalidResponse
        }
        let (data, response) = try await session.data(from: endpoint)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.invalidResponse
        }
        
        let decodedImages: [ImageNode]
        do {
            decodedImages = try JSONDecoder().decode([ImageNode].self, from: data)
        } catch is DecodingError {
            throw NetworkError.decodingFailed
        }

        var images = decodedImages
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

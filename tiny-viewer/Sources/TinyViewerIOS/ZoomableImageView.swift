import SwiftUI
import UIKit
import Kingfisher

public struct ZoomableImageView: View {
    let url: URL
    
    public init(url: URL) {
        self.url = url
    }
    
    public var body: some View {
        ZoomableImageViewRepresentable(url: url)
    }
}

struct ZoomableImageViewRepresentable: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> ZoomableScrollView {
        ZoomableScrollView()
    }
    
    func updateUIView(_ scrollView: ZoomableScrollView, context: Context) {
        scrollView.loadImage(from: url)
    }
}

class ZoomableScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var currentURL: URL?
    
    var isAtMinimumZoom: Bool {
        zoomScale <= minimumZoomScale + 0.01
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .black
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        decelerationRate = .fast
        bouncesZoom = true
        minimumZoomScale = 1.0
        maximumZoomScale = 5.0
        
        addSubview(imageView)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }
    
    func loadImage(from url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        
        setZoomScale(1.0, animated: false)
        imageView.image = nil
        
        imageView.kf.setImage(with: url, options: [.transition(.fade(0.2))]) { [weak self] result in
            if case .success = result {
                self?.configureForImageSize()
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if imageView.image != nil && zoomScale == 1.0 {
            configureForImageSize()
        }
    }
    
    private func configureForImageSize() {
        guard let image = imageView.image else { return }
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        let widthScale = bounds.width / imageSize.width
        let heightScale = bounds.height / imageSize.height
        let minScale = min(widthScale, heightScale)
        
        let imageWidth = imageSize.width * minScale
        let imageHeight = imageSize.height * minScale
        
        imageView.frame = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        contentSize = imageView.frame.size
        
        centerImage()
    }
    
    private func centerImage() {
        let offsetX = max((bounds.width - contentSize.width) / 2, 0)
        let offsetY = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let center = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
            zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }
}

import SwiftUI
import UIKit
import TinyViewerCore

public struct GalleryPageView: View {
    @ObservedObject var viewModel: GalleryViewModel
    
    public init(viewModel: GalleryViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else if viewModel.images.isEmpty {
                Text("No images")
                    .foregroundColor(.gray)
            } else {
                PageViewController(
                    images: viewModel.images,
                    config: viewModel.config,
                    currentIndex: $viewModel.currentIndex
                )
                .ignoresSafeArea()
            }
        }
        .onChangeCompat(of: viewModel.currentIndex) {
            viewModel.prefetchNearbyImages()
        }
    }
}

struct PageViewController: UIViewControllerRepresentable {
    let images: [ImageNode]
    let config: ImageGalleryConfig
    @Binding var currentIndex: Int
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator
        pageVC.view.backgroundColor = .black
        
        for subview in pageVC.view.subviews {
            if let scrollView = subview as? UIScrollView {
                scrollView.delaysContentTouches = false
                scrollView.canCancelContentTouches = true
            }
        }
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDismissPan(_:)))
        panGesture.delegate = context.coordinator
        pageVC.view.addGestureRecognizer(panGesture)
        context.coordinator.dismissPanGesture = panGesture
        context.coordinator.pageViewController = pageVC
        
        if let initialVC = context.coordinator.viewController(at: currentIndex) {
            pageVC.setViewControllers([initialVC], direction: .forward, animated: false)
        }
        
        return pageVC
    }
    
    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        guard let currentVC = pageVC.viewControllers?.first as? ImageHostingController,
              currentVC.index != currentIndex else { return }
        
        if let targetVC = context.coordinator.viewController(at: currentIndex) {
            let direction: UIPageViewController.NavigationDirection = currentIndex > currentVC.index ? .forward : .reverse
            pageVC.setViewControllers([targetVC], direction: direction, animated: true)
        }
    }
    
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PageViewController
        private var viewControllerCache: [Int: ImageHostingController] = [:]
        weak var dismissPanGesture: UIPanGestureRecognizer?
        weak var pageViewController: UIPageViewController?
        
        private var initialTouchPoint: CGPoint = .zero
        private var isDismissing = false
        
        init(_ parent: PageViewController) {
            self.parent = parent
        }
        
        func viewController(at index: Int) -> ImageHostingController? {
            guard index >= 0, index < parent.images.count else { return nil }
            
            if let cached = viewControllerCache[index] {
                return cached
            }
            
            let image = parent.images[index]
            guard let url = parent.config.imageURL(for: image) else { return nil }
            let vc = ImageHostingController(index: index, url: url)
            
            if viewControllerCache.count > 5 {
                let indicesToRemove = viewControllerCache.keys.filter { abs($0 - index) > 2 }
                indicesToRemove.forEach { viewControllerCache.removeValue(forKey: $0) }
            }
            viewControllerCache[index] = vc
            
            return vc
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ImageHostingController else { return nil }
            let newIndex = (vc.index - 1 + parent.images.count) % parent.images.count
            return self.viewController(at: newIndex)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let vc = viewController as? ImageHostingController else { return nil }
            let newIndex = (vc.index + 1) % parent.images.count
            return self.viewController(at: newIndex)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed,
                  let currentVC = pageViewController.viewControllers?.first as? ImageHostingController else { return }
            parent.currentIndex = currentVC.index
        }
        
        // MARK: - Dismiss Gesture
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
        
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            
            let velocity = pan.velocity(in: pan.view)
            let isVertical = abs(velocity.y) > abs(velocity.x)
            let isDownward = velocity.y > 0
            
            guard let currentVC = pageViewController?.viewControllers?.first as? ImageHostingController else {
                return false
            }
            
            return isVertical && isDownward && currentVC.isAtMinimumZoom
        }
        
        @objc func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)
            
            switch gesture.state {
            case .began:
                initialTouchPoint = view.center
                isDismissing = true
                
            case .changed:
                guard isDismissing else { return }
                let progress = max(0, translation.y) / view.bounds.height
                let scale = 1 - progress * 0.3  // 70% min size
                let newY = initialTouchPoint.y + translation.y
                
                view.center = CGPoint(x: initialTouchPoint.x, y: newY)
                view.transform = CGAffineTransform(scaleX: scale, y: scale)
                view.alpha = 1 - progress * 0.5
                
            case .ended, .cancelled:
                guard isDismissing else { return }
                isDismissing = false
                
                let shouldDismiss = translation.y > 150 || velocity.y > 800
                
                if shouldDismiss {
                    UIView.animate(withDuration: 0.2, animations: {
                        view.center = CGPoint(x: self.initialTouchPoint.x, y: view.bounds.height * 1.5)
                        view.alpha = 0
                    }) { _ in
                        self.suspendApp()
                    }
                } else {
                    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
                        view.center = self.initialTouchPoint
                        view.transform = .identity
                        view.alpha = 1
                    }
                }
                
            default:
                break
            }
        }
        
        private func suspendApp() {
            UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
        }
    }
}

class ImageHostingController: UIViewController {
    let index: Int
    let url: URL
    private var zoomableView: ZoomableScrollView?
    
    var isAtMinimumZoom: Bool {
        zoomableView?.isAtMinimumZoom ?? true
    }
    
    init(index: Int, url: URL) {
        self.index = index
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        let scrollView = ZoomableScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrollView)
        zoomableView = scrollView
        
        scrollView.loadImage(from: url)
    }
}

#if os(iOS)
import SwiftUI
import UIKit

/// Puts the left-edge swipe back.
///
/// Hiding the navigation bar takes the interactive pop gesture with it: UIKit
/// disables `interactivePopGestureRecognizer` whenever the bar is hidden, on the
/// assumption that a screen without a bar has no back button the gesture could
/// mirror. This screen draws its own back button, so the assumption does not
/// hold — and on a phone the edge swipe is how people actually go back. The
/// comment in FolderView used to claim the gesture "stays with the system";
/// it does not, and `testEdgeSwipeGoesBack` is the proof.
///
/// The delegate is taken over rather than set to nil. Nil is the recipe found
/// everywhere, and it re-enables the gesture — including on the root, where
/// there is nothing to pop: UIKit then leaves the navigation controller in a
/// state where the next push does not animate and the stack stops responding.
/// Answering "only when there is something to go back to" avoids that.
struct InteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        Enabler(coordinator: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigation: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigation?.viewControllers.count ?? 0) > 1
        }
    }

    /// A zero-sized controller whose only job is to be inside the navigation
    /// controller, which is the one place its `navigationController` property
    /// can be reached from.
    private final class Enabler: UIViewController {
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        // Not `viewDidLoad`: a zero-sized representable's view can be loaded
        // before it is in the hierarchy, and `navigationController` is nil then.
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            guard let navigation = navigationController else { return }
            coordinator.navigation = navigation
            navigation.interactivePopGestureRecognizer?.delegate = coordinator
        }
    }
}
#endif

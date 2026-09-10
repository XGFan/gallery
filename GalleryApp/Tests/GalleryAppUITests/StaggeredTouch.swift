#if os(iOS)
import ObjectiveC
import UIKit
import XCTest

/// Two fingers that land, move and leave at different times.
///
/// XCTest cannot make one. `pinch`, `rotate` and
/// `tap(withNumberOfTaps:numberOfTouches:)` all put both fingers down in the
/// same instant and move them symmetrically, and iOS refuses to read a touch
/// like that as a tap all by itself — none of them reproduced the bug these
/// tests cover, and the multi-touch taps could not even be aimed ("unable to
/// compute coordinates for gesture"). A hand does something else: one finger
/// lands first and then barely moves while the other does the spreading, and to
/// the view underneath the still one is an ordinary press.
///
/// Building that needs XCTest's own event-path API, which is private. It is
/// used here and nowhere else. `isAvailable` is checked first so that an Xcode
/// which renames any of it makes these tests skip with a message saying the
/// synthesiser needs repairing, rather than crashing the runner — which is what
/// getting a detail of it wrong does.
enum StaggeredTouch {
    /// The finger that stays put presses at `holding` for the whole gesture.
    /// The other lands at `dragging` 100ms later, travels to `to` — pulling the
    /// two apart, which is a pinch — and leaves first.
    static func pinch(holding: CGPoint, dragging: CGPoint, to end: CGPoint) {
        guard let pathClass = NSClassFromString("XCPointerEventPath"),
              let recordClass = NSClassFromString("XCSynthesizedEventRecord"),
              let sessionClass = NSClassFromString("XCTRunnerDaemonSession")
        else { return }

        let (touchInit, touchInitSelector) = implementation(
            pathClass, "initForTouchAtPoint:offset:", as: InitTouch.self
        )
        let (liftUp, liftUpSelector) = implementation(pathClass, "liftUpAtOffset:", as: AtOffset.self)
        let (moveTo, moveToSelector) = implementation(pathClass, "moveToPoint:atOffset:", as: MoveTo.self)

        let anchor = touchInit(allocate(pathClass), touchInitSelector, holding, 0)
        liftUp(anchor, liftUpSelector, 1.20)

        // Stepped, not one jump to the far end: a single move event is a
        // discontinuity that the pinch recogniser does not read as a pinch at
        // all — the wall stayed at two columns while the touches plainly
        // arrived. A finger travels.
        let spreader = touchInit(allocate(pathClass), touchInitSelector, dragging, 0.10)
        for step in 1...Self.spreadSteps {
            let progress = CGFloat(step) / CGFloat(Self.spreadSteps)
            moveTo(
                spreader, moveToSelector,
                CGPoint(
                    x: dragging.x + (end.x - dragging.x) * progress,
                    y: dragging.y + (end.y - dragging.y) * progress
                ),
                0.20 + 0.80 * Double(progress)
            )
        }
        liftUp(spreader, liftUpSelector, 1.10)

        let (recordInit, recordInitSelector) = implementation(
            recordClass, "initWithName:interfaceOrientation:", as: InitRecord.self
        )
        let record = recordInit(
            allocate(recordClass), recordInitSelector, "staggered pinch" as NSString,
            Int(UIInterfaceOrientation.portrait.rawValue)
        )
        let addPath = NSSelectorFromString("addPointerEventPath:")
        _ = record.perform(addPath, with: anchor)
        _ = record.perform(addPath, with: spreader)

        let session = (sessionClass as AnyObject)
            .perform(NSSelectorFromString("sharedSession"))!.takeUnretainedValue()
        let (synthesize, synthesizeSelector) = implementation(
            object_getClass(session)!, "synthesizeEvent:completion:", as: Synthesize.self
        )

        // Synchronous, like every XCUIElement gesture: the caller looks at the
        // app straight afterwards.
        let delivered = DispatchSemaphore(value: 0)
        synthesize(session, synthesizeSelector, record) { _, _ in delivered.signal() }
        _ = delivered.wait(timeout: .now() + 15)
    }

    /// How many move events the spreading finger's travel is broken into.
    private static let spreadSteps = 20

    /// Whether the private API this is built on is still shaped the way it was.
    static var isAvailable: Bool {
        guard let pathClass = NSClassFromString("XCPointerEventPath"),
              let recordClass = NSClassFromString("XCSynthesizedEventRecord"),
              let sessionClass = NSClassFromString("XCTRunnerDaemonSession")
        else { return false }
        let pathSelectors = ["initForTouchAtPoint:offset:", "liftUpAtOffset:", "moveToPoint:atOffset:"]
        guard pathSelectors.allSatisfy({ responds(pathClass, to: $0) }),
              responds(recordClass, to: "initWithName:interfaceOrientation:"),
              responds(recordClass, to: "addPointerEventPath:"),
              responds(sessionClass, to: "synthesizeEvent:completion:"),
              (sessionClass as AnyObject).responds(to: NSSelectorFromString("sharedSession"))
        else { return false }
        return true
    }

    private static func responds(_ cls: AnyClass, to name: String) -> Bool {
        class_getInstanceMethod(cls, NSSelectorFromString(name)) != nil
    }

    private static func allocate(_ cls: AnyClass) -> AnyObject {
        (cls as AnyObject).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
    }

    private static func implementation<T>(
        _ cls: AnyClass, _ name: String, as type: T.Type
    ) -> (T, Selector) {
        let selector = NSSelectorFromString(name)
        let pointer = class_getMethodImplementation(cls, selector)!
        return (unsafeBitCast(pointer, to: T.self), selector)
    }

    // Called through typed IMPs rather than `perform`, which cannot pass a
    // CGPoint or a TimeInterval.
    private typealias InitTouch = @convention(c) (AnyObject, Selector, CGPoint, Double) -> AnyObject
    private typealias AtOffset = @convention(c) (AnyObject, Selector, Double) -> Void
    private typealias MoveTo = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
    private typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
    private typealias Synthesize = @convention(c) (
        AnyObject, Selector, AnyObject, @escaping Completion
    ) -> Void
    /// The completion's parameters are taken as raw words on purpose: declared
    /// as `Error?`, the bridging thunk retained what turned out to be a `BOOL`
    /// and took the runner down with a segfault.
    private typealias Completion = @convention(block) (UnsafeRawPointer?, UnsafeRawPointer?) -> Void
}
#endif

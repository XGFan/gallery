import AppKit
import SwiftUI
import TinyViewerCore

public class GalleryWindow: NSWindow {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    
    public var onDragEnded: (() -> Void)?
    
    public override func mouseDown(with event: NSEvent) {
        if isOnResizeCorner(event: event) {
            return
        }
        performDrag(with: event)
    }
    
    public override func mouseDragged(with event: NSEvent) {
        if isOnResizeCorner(event: event) {
            return
        }
        performDrag(with: event)
    }
    
    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onDragEnded?()
    }
    
    private func isOnResizeCorner(event: NSEvent) -> Bool {
        let location = event.locationInWindow
        let cornerSize: CGFloat = 16
        let bounds = contentView?.bounds ?? .zero
        
        let nearRight = location.x >= bounds.width - cornerSize
        let nearBottom = location.y <= cornerSize
        
        return nearRight && nearBottom
    }
}

public class GalleryWindowController: NSWindowController {
    private var currentCenter: CGPoint?
    private var diagonalScale: CGFloat = 1.0
    private var currentImageSize: CGSize?
    private var lastFrameSize: CGSize?
    private let debug = ProcessInfo.processInfo.environment["DEBUG"] != nil
    
    public convenience init() {
        let window = GalleryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.contentAspectRatio = NSSize(width: 4, height: 3)
        window.center()
        
        self.init(window: window)
        
        window.onDragEnded = { [weak self] in
            self?.handleMouseUp()
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEndLiveResize),
            name: NSWindow.didEndLiveResizeNotification,
            object: window
        )
    }
    
    @objc private func windowDidEndLiveResize() {
        if debug {
            print("[event] windowDidEndLiveResize triggered")
        }
        saveScaleFromResize()
        updateCenterAfterDrag()
    }
    
    private func handleMouseUp() {
        updateCenterAfterDrag()
    }
    
    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        currentCenter = windowCenter
    }
    
    private var windowCenter: CGPoint? {
        guard let frame = window?.frame else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }
    
    private func diagonal(_ size: CGSize) -> CGFloat {
        sqrt(size.width * size.width + size.height * size.height)
    }
    
    private func defaultSize(for imageSize: CGSize, in visibleFrame: CGRect) -> CGSize {
        let aspectRatio = imageSize.width / imageSize.height
        
        var defaultWidth = min(imageSize.width, visibleFrame.width)
        var defaultHeight = defaultWidth / aspectRatio
        
        if defaultHeight > visibleFrame.height {
            defaultHeight = min(imageSize.height, visibleFrame.height)
            defaultWidth = defaultHeight * aspectRatio
        }
        
        return CGSize(width: defaultWidth, height: defaultHeight)
    }
    
    public func resizeWindow(toFit imageSize: CGSize, animated: Bool = true) {
        guard let window = window,
              let screen = window.screen ?? NSScreen.main else { return }
        
        let visibleFrame = screen.visibleFrame
        let center = currentCenter ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        
        currentImageSize = imageSize
        let aspectRatio = imageSize.width / imageSize.height
        window.contentAspectRatio = NSSize(width: imageSize.width, height: imageSize.height)
        
        let defaultSz = defaultSize(for: imageSize, in: visibleFrame)
        var newWidth = defaultSz.width * diagonalScale
        var newHeight = defaultSz.height * diagonalScale
        
        if newWidth > visibleFrame.width {
            newWidth = visibleFrame.width
            newHeight = newWidth / aspectRatio
        }
        if newHeight > visibleFrame.height {
            newHeight = visibleFrame.height
            newWidth = newHeight * aspectRatio
        }
        
        if debug {
            print("[resize] imageSize: \(Int(imageSize.width))x\(Int(imageSize.height)), defaultSize: \(Int(defaultSz.width))x\(Int(defaultSz.height)), windowSize: \(Int(newWidth))x\(Int(newHeight)), scale: \(String(format: "%.3f", diagonalScale))")
        }
        
        let newOrigin = CGPoint(
            x: center.x - newWidth / 2,
            y: center.y - newHeight / 2
        )
        
        let newFrame = NSRect(origin: newOrigin, size: CGSize(width: newWidth, height: newHeight))
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
        
        currentCenter = center
    }
    
    public func centerOnScreen() {
        guard let window = window,
              let screen = window.screen ?? NSScreen.main else { return }
        
        let visibleFrame = screen.visibleFrame
        currentCenter = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        
        let frame = window.frame
        let newOrigin = CGPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        window.setFrameOrigin(newOrigin)
    }
    
    public func scaleWindow(by factor: CGFloat) {
        guard let window = window,
              let screen = window.screen ?? NSScreen.main,
              let imageSize = currentImageSize else { return }
        
        let visibleFrame = screen.visibleFrame
        let center = currentCenter ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        let aspectRatio = imageSize.width / imageSize.height
        
        let currentFrame = window.frame
        var newWidth = currentFrame.width * factor
        var newHeight = currentFrame.height * factor
        
        let minDimension: CGFloat = 300
        if newWidth < minDimension && newHeight < minDimension {
            if aspectRatio > 1 {
                newWidth = minDimension
                newHeight = minDimension / aspectRatio
            } else {
                newHeight = minDimension
                newWidth = minDimension * aspectRatio
            }
        }
        
        if newWidth > visibleFrame.width {
            newWidth = visibleFrame.width
            newHeight = newWidth / aspectRatio
        }
        if newHeight > visibleFrame.height {
            newHeight = visibleFrame.height
            newWidth = newHeight * aspectRatio
        }
        
        let newOrigin = CGPoint(
            x: center.x - newWidth / 2,
            y: center.y - newHeight / 2
        )
        
        let newFrame = NSRect(origin: newOrigin, size: CGSize(width: newWidth, height: newHeight))
        window.setFrame(newFrame, display: true, animate: true)
        
        let defaultSz = defaultSize(for: imageSize, in: visibleFrame)
        diagonalScale = diagonal(CGSize(width: newWidth, height: newHeight)) / diagonal(defaultSz)
        
        if debug {
            print("[scale] factor: \(factor), windowSize: \(Int(newWidth))x\(Int(newHeight)), diagonalScale: \(String(format: "%.3f", diagonalScale))")
        }
    }
    
    public func updateCenterAfterDrag() {
        currentCenter = windowCenter
    }
    
    private func saveScaleFromResize() {
        guard let window = window,
              let screen = window.screen ?? NSScreen.main,
              let imageSize = currentImageSize else { return }
        
        let frame = window.frame
        let visibleFrame = screen.visibleFrame
        
        let defaultSz = defaultSize(for: imageSize, in: visibleFrame)
        let defaultDiagonal = diagonal(defaultSz)
        let currentDiagonal = diagonal(frame.size)
        
        diagonalScale = currentDiagonal / defaultDiagonal
        
        if debug {
            print("[resized] imageSize: \(Int(imageSize.width))x\(Int(imageSize.height)), defaultSize: \(Int(defaultSz.width))x\(Int(defaultSz.height)), windowSize: \(Int(frame.width))x\(Int(frame.height)), scale: \(String(format: "%.3f", diagonalScale))")
        }
    }
}

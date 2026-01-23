import AppKit
import SwiftUI
import TinyViewerMacOS
import TinyViewerCore

@main
struct TinyViewerApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: GalleryWindowController?
    var viewModel: GalleryViewModel?
    var eventMonitor: Any?
    var hasHandledURL = false
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let imageLoader = ImageLoader()
        imageLoader.configureKingfisher()
        
        setupKeyboardHandling()
        
        // If URL was already handled by handleURLEvent, don't load default
        if !hasHandledURL {
            let category = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
            loadCategory(category)
        }
    }
    
    func loadCategory(_ category: String) {
        let baseURL = ProcessInfo.processInfo.environment["GALLERY_API_URL"] ?? "https://gallery.test4x.com"
        let config = ImageGalleryConfig(baseURL: baseURL, category: category)
        
        viewModel = GalleryViewModel(config: config)
        
        if windowController == nil {
            windowController = GalleryWindowController()
        }
        
        setupContentView()
        windowController?.show()
        
        if !hasHandledURL { // Only center on initial launch
            windowController?.centerOnScreen()
        }
        
        Task {
            await viewModel?.loadImages()
            if let vm = viewModel, vm.images.isEmpty {
                showErrorAndQuit()
            }
        }
    }
    
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        hasHandledURL = true
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else { return }
        
        // Handle encoded URL strings
        let category = parseCategory(from: urlString)
        loadCategory(category)
    }
    
    private func parseCategory(from urlString: String) -> String {
        // Remove scheme if present
        var path = urlString
        if path.hasPrefix("tinyviewer://") {
            path = String(path.dropFirst("tinyviewer://".count))
        }
        
        // Decode URL components (handles %20, %E4%BD%A0 etc)
        if let decoded = path.removingPercentEncoding {
            path = decoded
        }
        
        // Clean up path
        // 1. Remove query parameters if present
        if let queryIndex = path.firstIndex(of: "?") {
            path = String(path[..<queryIndex])
        }
        
        // 2. Remove leading/trailing slashes
        path = path.trimmingCharacters(in: .init(charactersIn: "/"))
        
        // 3. Handle specific "open?category=" case
        if urlString.contains("category=") {
            if let components = URLComponents(string: urlString),
               let queryItem = components.queryItems?.first(where: { $0.name == "category" }),
               let value = queryItem.value {
                return value
            }
        }
        
        return path
    }
    
    func setupContentView() {
        guard let viewModel = viewModel, let window = windowController?.window else { return }
        
        let wc = windowController
        let contentView = GalleryContentView(viewModel: viewModel) { @MainActor size in
            wc?.resizeWindow(toFit: size, animated: true)
        }
        
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView
    }
    
    func setupKeyboardHandling() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            let isCommand = event.modifierFlags.contains(.command)
            
            switch event.keyCode {
            case 53: // ESC
                NSApp.terminate(nil)
                return nil
            case 12 where isCommand: // Cmd+Q
                NSApp.terminate(nil)
                return nil
            case 13 where isCommand: // Cmd+W
                NSApp.terminate(nil)
                return nil
            case 12: // Q (without modifier)
                NSApp.terminate(nil)
                return nil
            case 123: // Left arrow
                Task { @MainActor in
                    self.viewModel?.previousImage()
                }
                return nil
            case 124: // Right arrow
                Task { @MainActor in
                    self.viewModel?.nextImage()
                }
                return nil
            case 35: // P
                Task { @MainActor in
                    self.viewModel?.togglePlayback()
                }
                return nil
            case 8: // C - copy image URL
                if let url = self.currentImageURL() {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                return nil
            case 38: // J - open in browser
                if let url = self.currentImageURL() {
                    NSWorkspace.shared.open(url)
                }
                return nil
            case 24 where event.modifierFlags.contains(.control): // Ctrl+=+
                self.windowController?.scaleWindow(by: 1.15)
                return nil
            case 27 where event.modifierFlags.contains(.control): // Ctrl+-
                self.windowController?.scaleWindow(by: 0.87)
                return nil
            default:
                return event
            }
        }
    }
    
    func showErrorAndQuit() {
        let alert = NSAlert()
        alert.messageText = "No images found"
        alert.informativeText = "Could not load images from the server."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.terminate(nil)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func currentImageURL() -> URL? {
        guard let vm = viewModel, let image = vm.currentImage else { return nil }
        return vm.config.imageURL(for: image)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

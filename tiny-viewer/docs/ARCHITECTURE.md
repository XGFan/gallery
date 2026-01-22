# tiny-viewer Architecture

## Project Structure

```
tiny-viewer/
├── Package.swift
├── Sources/
│   ├── TinyViewerCore/          # Platform-agnostic shared logic
│   │   ├── Models.swift         # Data models
│   │   ├── NetworkManager.swift # API client
│   │   └── ImageLoader.swift    # Kingfisher configuration
│   ├── TinyViewerMacOS/         # macOS-specific UI
│   │   ├── GalleryWindowController.swift
│   │   └── GalleryContentView.swift
│   ├── TinyViewerIOS/           # iOS-specific UI
│   │   ├── ZoomableImageView.swift
│   │   ├── GalleryPageView.swift
│   │   ├── GalleryViewModel.swift
│   │   └── GalleryContainerView.swift
│   └── TinyViewerMain/          # macOS executable entry point
│       └── main.swift
├── TinyViewerApp/               # iOS app (Xcode project)
│   ├── TinyViewerApp.swift
│   ├── TinyViewerApp.xcodeproj/
│   ├── Assets.xcassets/         # App icon
│   └── Info.plist
├── Resources/
│   └── AppIcon.icns             # macOS app icon
├── scripts/
│   └── package-macos.sh         # macOS .app packaging script
├── dist/                        # Packaged macOS app output
│   └── TinyViewer.app
└── docs/
```

## Module Dependencies

```
macOS:
TinyViewerMain
    └── TinyViewerMacOS
            └── TinyViewerCore
                    └── Kingfisher

iOS:
TinyViewerApp (Xcode project)
    └── TinyViewerIOS
            └── TinyViewerCore
                    └── Kingfisher
```

## Components

### TinyViewerCore (Shared)

#### ImageGalleryConfig
Configuration holder for API endpoints.

```swift
struct ImageGalleryConfig {
    let baseURL: String      // Base URL (default: https://gallery.test4x.com)
    let category: String     // Category filter
    var apiEndpoint: URL?    // Computed: {baseURL}/api/image/{category}
    func imageURL(for:) -> URL?  // Constructs image URL from node
}
```

> **URL Encoding**: `imageURL(for:)` supports both raw paths (e.g., `Weibo/kyokyo不是qq啊`) and already percent-encoded paths (e.g., `Weibo/kyokyo%E4%B8%8D%E6%98%AFqq%E5%95%8A`).

#### ImageNode
Represents a single image from the API.

```swift
struct ImageNode: Codable, Identifiable {
    let name: String
    let path: String
    let width: Int?
    let height: Int?
    var aspectRatio: CGFloat  // Computed
}
```

#### NetworkManager
Singleton API client.

```swift
class NetworkManager {
    static let shared: NetworkManager
    func fetchImages(config:) async throws -> [ImageNode]  // Fetches & shuffles
}
```

#### ImageLoader
Kingfisher cache configuration (macOS only).

```swift
class ImageLoader {
    func configureKingfisher()  // Sets memory (100MB) & disk (500MB) limits
}
```

> **Note**: Only macOS explicitly calls `configureKingfisher()`. iOS uses Kingfisher's default cache settings:
> - Memory: 25% of device RAM
> - Disk: No limit (system managed)

---

### TinyViewerMacOS

#### GalleryWindow (NSWindow subclass)
Custom window with drag support.

- Overrides `canBecomeKey`, `canBecomeMain` → true
- Handles mouse events for window dragging
- Excludes 16x16 bottom-right corner for resize handle
- Callback `onDragEnded` for position updates

#### GalleryWindowController
Window management and scaling logic.

Key properties:
- `currentCenter: CGPoint?` - Anchor point for center-based resizing
- `diagonalScale: CGFloat` - User's zoom preference (1.0 = default)
- `currentImageSize: CGSize?` - Current image dimensions

Key methods:
```swift
func show()                                    // Display window
func centerOnScreen()                          // Center on screen
func resizeWindow(toFit:animated:)             // Fit to image with scale
func scaleWindow(by:)                          // Keyboard zoom
func updateCenterAfterDrag()                   // Update anchor after drag
```

#### GalleryContentView (SwiftUI View)
Image display with Kingfisher.

- Uses `KFImage` for loading/caching
- Reports image size via callback on load success
- Shows play indicator when slideshow active

#### GalleryViewModel (macOS)
State management with slideshow support.

> **Note**: macOS and iOS have separate `GalleryViewModel` implementations:
> - **macOS** (`TinyViewerMacOS/GalleryContentView.swift`): Includes slideshow (`isPlaying`, `togglePlayback()`)
> - **iOS** (`TinyViewerIOS/GalleryViewModel.swift`): Simplified, no slideshow
> 
> Future refactoring may extract shared logic to `TinyViewerCore`.

```swift
class GalleryViewModel {
    @Published var images: [ImageNode]
    @Published var currentIndex: Int
    @Published var isLoading: Bool
    @Published var isPlaying: Bool
    
    func loadImages() async
    func nextImage()
    func previousImage()
    func togglePlayback()
    func prefetchNearbyImages()
}
```

---

### TinyViewerIOS

#### ZoomableScrollView (UIScrollView subclass)
UIScrollView-based pinch-to-zoom image container.

- Supports pinch zoom (1x - 5x)
- Double-tap to zoom in/out
- Auto-centers image during zoom via contentInset
- Exposes `isAtMinimumZoom` for dismiss gesture coordination
- Resets zoom on image change

##### Double-Tap Zoom Behavior
- **If zoomed in** (scale > 1x): Animates back to fit-to-screen (1x)
- **If at 1x**: Zooms to ~2.5x centered on tap location
  - Zoom target: A rect of size `bounds / 2.5` centered on tap point

#### ZoomableImageView (SwiftUI Wrapper)
Optional SwiftUI wrapper around `ZoomableScrollView`.

```swift
struct ZoomableImageView: View {
    let url: URL
}
```

> **Note**: Currently unused in the app. Provided as a reusable SwiftUI component for future use or external integration.

#### GalleryPageView
UIPageViewController-based swipeable gallery with dismiss gesture.

- Uses UIPageViewController for horizontal swipe navigation
- UIPanGestureRecognizer for swipe-down-to-dismiss
- Dismiss only triggers when image is at 1x zoom
- Visual feedback: scale + fade animation during dismiss
- Suspends app on dismiss (returns to previous app)

##### ViewController Caching
`PageViewController.Coordinator` maintains a cache of `ImageHostingController` instances:

- **Cache Size**: Maximum 5 controllers
- **Eviction Policy**: When cache exceeds 5 items, removes controllers where `abs(cachedIndex - currentIndex) > 2`
- **Purpose**: Balances memory usage with smooth swiping experience

```
Cache visualization (currentIndex = 5):
Kept:     [3] [4] [5] [6] [7]
Evicted:  [0] [1] [2]       [8] [9] ...
```

##### Dismiss Gesture Implementation

The dismiss gesture uses a `UIPanGestureRecognizer` with the following logic:

1. **Gesture Recognition Conditions**:
   - Vertical swipe (`abs(velocity.y) > abs(velocity.x)`)
   - Downward direction (`velocity.y > 0`)
   - Image at minimum zoom (1x)

2. **Visual Feedback During Swipe**:
   - Scale: 1.0 → 0.7 (based on progress)
   - Alpha: 1.0 → 0.5 (based on progress)
   - Position: follows finger vertically

3. **Dismiss Threshold**:
   - Distance: > 150px, OR
   - Velocity: > 800px/s

4. **App Suspension** (`suspendApp()`):
   Uses `UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)` to suspend the app and return to the previous app.

   > ⚠️ **Warning**: This is a private API trick. It works reliably but may be rejected by App Store review. For personal/enterprise distribution, this is acceptable.

#### HideSystemOverlaysModifier
A `ViewModifier` that hides the home indicator on iOS 16+.

```swift
struct HideSystemOverlaysModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.persistentSystemOverlays(.hidden)
        } else {
            content  // No-op on iOS 15
        }
    }
}
```

Applied in `GalleryContainerView` for full-screen immersion.

#### GalleryViewModel (iOS)
Simplified state management (no slideshow).

```swift
class GalleryViewModel {
    @Published var images: [ImageNode]
    @Published var currentIndex: Int
    @Published var isLoading: Bool
    
    func loadImages() async
    func nextImage()
    func previousImage()
    func prefetchNearbyImages()
}
```

#### GalleryContainerView
Root view that initializes ViewModel and handles lifecycle.

```swift
struct GalleryContainerView: View {
    init(category: String = "")  // Category for API filter
}
```

---

### TinyViewerApp (iOS)

#### TinyViewerApp.swift
SwiftUI App entry point with URL scheme handling.

```swift
@main
struct TinyViewerApp: App {
    // Handles tinyviewer:// URL scheme
    // Parses category from URL host, path, or query parameter
}
```

#### Info.plist
- Registers `tinyviewer://` URL scheme
- Supports all orientations
- Hidden status bar

#### Assets.xcassets
- AppIcon.appiconset with all required iOS icon sizes

---

## Data Flow

### macOS
```
User Action (Keyboard)
    ↓
Keyboard Event Monitor (main.swift)
    ↓
ViewModel.nextImage() / togglePlayback() / etc.
    ↓
@Published property changes
    ↓
SwiftUI re-renders GalleryContentView
    ↓
KFImage loads new image
    ↓
onSuccess callback with image size
    ↓
WindowController.resizeWindow(toFit:)
    ↓
Window animates to new frame
```

### iOS
```
User Gesture (Swipe / Pinch / Swipe Down)
    ↓
UIPageViewController / UIScrollView / UIPanGestureRecognizer
    ↓
├── Horizontal swipe → Page change → ViewModel.currentIndex update
├── Pinch → ZoomableScrollView zoom
└── Swipe down (at 1x zoom) → Dismiss animation → App suspend
    ↓
Returns to previous app/Safari
```

---

## Key Algorithms

### Center-Anchored Resize (macOS)
1. Store `currentCenter` as window midpoint
2. Calculate new size based on image + scale
3. Compute new origin: `center - size/2`
4. Animate to new frame

### Window Scaling Algorithm (macOS - Detailed)

#### Key Concepts

1. **Default Size**: The size a window would be if `diagonalScale = 1.0`
   - Fits image within screen's visible frame
   - Maintains aspect ratio
   - Never exceeds screen bounds

2. **Diagonal Scale**: Ratio of current window diagonal to default diagonal
   ```
   diagonalScale = diagonal(currentWindowSize) / diagonal(defaultWindowSize)
   ```

3. **Center Anchor**: Window resizes around its center point, not origin

#### Resize Flow (Manual Drag)

```
User drags resize corner
    ↓
windowDidEndLiveResize()
    ↓
saveScaleFromResize()  →  Updates diagonalScale
    ↓
updateCenterAfterDrag()  →  Updates currentCenter
```

#### Image Switch Flow

```
New image loaded
    ↓
resizeWindow(toFit: imageSize)
    ↓
Calculate defaultSize for new image
    ↓
Apply saved diagonalScale  →  newSize = defaultSize × diagonalScale
    ↓
Clamp to screen bounds
    ↓
Calculate origin from currentCenter
    ↓
Animate to new frame
```

#### Keyboard Zoom Flow

```
Ctrl+= or Ctrl+-
    ↓
scaleWindow(by: factor)  // 1.15 or 0.87
    ↓
newSize = currentSize × factor
    ↓
Clamp to [300px min, screen max]
    ↓
Update diagonalScale from new size
    ↓
Animate to new frame (center-anchored)
```

### Fit-to-Screen Zoom (iOS)
```
scale = min(boundsWidth / imageWidth, boundsHeight / imageHeight)
imageFrame = image * scale, centered in bounds
```

### Prefetching (Both platforms)
```
indices = [current-3, current-2, current-1, current+1, current+2, current+3]
```

---

## URL Scheme (iOS)

| URL | Result |
|-----|--------|
| `tinyviewer://` | Opens root gallery |
| `tinyviewer://Weibo` | Opens Weibo category |
| `tinyviewer://Weibo/SIREN` | Opens Weibo/SIREN subcategory |
| `tinyviewer://open?category=Weibo` | Opens Weibo category |

---

## macOS App Packaging

### Build Script
`scripts/package-macos.sh` creates a distributable .app bundle:

```bash
./scripts/package-macos.sh
```

### Bundle Structure
```
dist/TinyViewer.app/
└── Contents/
    ├── Info.plist          # App metadata, URL scheme
    ├── MacOS/
    │   └── TinyViewer      # Executable
    └── Resources/
        └── AppIcon.icns    # App icon
```

### Key Info.plist Settings
- `LSUIElement = true`: No Dock icon (accessory app)
- `CFBundleURLSchemes`: Registers `tinyviewer://` URL scheme
- `NSHighResolutionCapable = true`: Retina support

---

## External Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Kingfisher | 7.0+ | Image loading, caching, prefetching |

## Platform Requirements

| Platform | Minimum Version |
|----------|-----------------|
| macOS | 12.0+ |
| iOS | 15.0+ |
| Swift | 6.2+ |

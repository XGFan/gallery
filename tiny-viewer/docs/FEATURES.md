# tiny-viewer Features

A minimalist image gallery viewer for macOS and iOS.

---

## macOS Features

### Frameless Window
- Borderless floating window with shadow
- Always-on-top (floating level)
- Draggable by clicking anywhere on the image
- Resizable from bottom-right corner (16px hotzone)
- No Dock icon (accessory app mode)

### Image Loading
- Fetches images from `https://gallery.test4x.com/api/image/{category}`
- Automatic shuffle on load
- Kingfisher-powered caching (100MB memory, 500MB disk)
- Prefetches ±3 images for smooth navigation

### Window Behavior
- Center-anchored resizing (window expands/contracts from center)
- Aspect ratio locked to current image
- Scale memory: window size preference preserved across image navigation
- Animated transitions (0.2s) when switching images

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `←` | Previous image (loops) |
| `→` | Next image (loops) |
| `P` | Toggle slideshow play/pause |
| `C` | Copy current image URL to clipboard |
| `J` | Open current image URL in browser |
| `Ctrl + =` | Zoom in (~15%) |
| `Ctrl + -` | Zoom out (~13%) |
| `ESC` | Quit |
| `Q` | Quit |
| `Cmd + Q` | Quit |
| `Cmd + W` | Quit |

### Slideshow Mode
- Press `P` to start/stop automatic playback
- 3-second interval between images
- Small play indicator (▶) appears in bottom-right corner when active
- Semi-transparent (50% opacity) to be unobtrusive

### Window Scaling

#### Manual Resize
- Drag bottom-right corner to resize
- Aspect ratio maintained automatically
- Scale factor remembered for subsequent images

#### Keyboard Scaling
- `Ctrl + =`: Enlarge by 15%
- `Ctrl + -`: Shrink by ~13%
- Maximum: Screen visible area
- Minimum: At least 300px on one dimension

### Building & Packaging

#### Development
```bash
cd tiny-viewer
swift build && swift run tiny-viewer Weibo
```

#### Create App Bundle
```bash
./scripts/package-macos.sh
```

Output: `dist/TinyViewer.app`

#### Run Packaged App
```bash
open dist/TinyViewer.app --args Weibo
open dist/TinyViewer.app --args Weibo/SIREN
```

### Configuration

#### Command Line
```bash
tiny-viewer [category]
```
- `category`: Optional image category filter (e.g., `Weibo`, `Weibo/SIREN`)

#### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `GALLERY_API_URL` | Base URL for image API | `https://gallery.test4x.com` |
| `DEBUG` | Enable debug logging | (disabled) |

### Debug Mode
Set `DEBUG=1` to enable detailed logging:
```bash
DEBUG=1 swift run tiny-viewer Weibo
```

---

## iOS Features

### Gesture Navigation
- **Swipe left/right**: Navigate between images (loops at ends)
- **Pinch**: Zoom in/out on current image
- **Double-tap**: Toggle between 1x and 2.5x zoom
- **Swipe down**: Close app and return to previous app/Safari

### Swipe-to-Dismiss
When opened from another app or Safari via URL scheme:
- Swipe down to dismiss TinyViewer
- Automatically returns to the previous app/webpage
- Visual feedback: image scales down and fades during swipe
- Threshold: 150px distance or 800px/s velocity

### Image Display
- Full-screen, edge-to-edge display
- Fit-to-screen by default (shows complete image)
- Zoom resets to fit-to-screen when switching images
- Supports portrait and landscape orientations
- Hidden status bar for immersive viewing
- Hidden home indicator (iOS 16+) for full immersion

### Image Loading
- Same API as macOS: `https://gallery.test4x.com/api/image/{category}`
- Automatic shuffle on load
- Kingfisher-powered caching (default settings: 25% device RAM, unlimited disk)
- Prefetches ±3 images for smooth swiping

### URL Scheme
Open the app with a specific category via URL:

| URL | Result |
|-----|--------|
| `tinyviewer://` | Opens root gallery (all images) |
| `tinyviewer://Weibo` | Opens Weibo category |
| `tinyviewer://Weibo/SIREN` | Opens Weibo/SIREN subcategory |
| `tinyviewer://open?category=Weibo` | Opens Weibo category (query param) |

#### Usage Examples
```bash
# From Safari or other apps
tinyviewer://Weibo

# From terminal (simulator)
xcrun simctl openurl booted "tinyviewer://Weibo/SIREN"
```

### Building & Running

#### Open in Xcode
```bash
open TinyViewerApp/TinyViewerApp.xcodeproj
```

#### Build & Run
1. Select target device (iPhone/iPad)
2. Press `⌘R` to build and run

### App Icon
Custom app icon included in `Assets.xcassets/AppIcon.appiconset/`

---

## Comparison

| Feature | macOS | iOS |
|---------|-------|-----|
| Navigation | Arrow keys | Swipe gestures |
| Zoom | Ctrl+/-, mouse drag | Pinch, double-tap |
| Slideshow | Yes (P key) | No |
| Window resize | Yes | N/A (full-screen) |
| Copy URL | C key | No |
| Open in browser | J key | No |
| Category selection | Command line arg | URL scheme |
| Orientation | N/A | Portrait + Landscape |
| Dismiss/Close | ESC/Q/Cmd+Q/Cmd+W | Swipe down |
| Dock icon | No (accessory mode) | N/A |

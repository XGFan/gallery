#!/bin/bash
set -e

cd "$(dirname "$0")/.."

APP_NAME="TinyViewer"
BUNDLE_ID="com.tinyviewer.macos"
EXECUTABLE="tiny-viewer"
BUILD_DIR=".build/release"
OUTPUT_DIR="dist"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

echo "Building release..."
swift build -c release --product tiny-viewer

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>TinyViewer URL</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>tinyviewer</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

echo "Done! App bundle created at: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "To run with category: open $APP_BUNDLE --args Weibo"

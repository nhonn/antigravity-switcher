#!/bin/bash
set -e

APP_NAME="AntigravityMenuBar"
BUILD_DIR=".build/release"
APP_BUNDLE_DIR="build/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🚀 Building Swift App..."
swift build -c release --arch arm64

echo "📦 Creating .app Bundle..."
rm -rf "$APP_BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy Binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.ctrler.antigravity.menubar</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Copy Icon
if [ -f "assets/icon.icns" ]; then
    cp "assets/icon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

echo "🎉 Build Complete!"
echo "📂 App location: $APP_BUNDLE_DIR"
echo "ℹ️  Run with: open '$APP_BUNDLE_DIR'"

#!/bin/zsh
set -e
cd "$(dirname "$0")/.."
swift build -c release --build-system native 2>&1 | grep -v "ld: warning" | tail -2
BIN=$(swift build -c release --build-system native --show-bin-path 2>/dev/null)/Sophia
APP=build/Sophia.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Sophia"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.sophia.app</string>
  <key>CFBundleName</key><string>Sophia</string>
  <key>CFBundleExecutable</key><string>Sophia</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-0.1.0}</string>
  <key>CFBundleVersion</key><string>${BUILD:-1}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSSpeechRecognitionUsageDescription</key><string>Speech is recognised on this Mac to hear the wake phrase and what you say. Nothing is sent anywhere.</string>
  <key>NSAppleEventsUsageDescription</key><string>Sophia can control music, dark mode and type text for you, only from a fixed list of actions and only when you ask.</string>
  <key>NSMicrophoneUsageDescription</key><string>Sophia listens for the wake phrase and records what you say after it. Audio stays on this Mac.</string>
</dict></plist>
PLIST
IDENTITY="${SOPHIA_SIGN_IDENTITY:--}"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP" 2>&1 | grep -v "replacing existing signature" || true
echo "Built $APP (signed with: $IDENTITY)"

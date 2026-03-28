#!/bin/zsh

set -euo pipefail

ROOT="/Users/hht/workspace/ProxyBridge"
PROJECT="$ROOT/MacOS/ProxyTun/ProxyTun.xcodeproj"
DERIVED_DATA="$ROOT/.build/ProxyTun-macos"
APP_PATH="$DERIVED_DATA/Build/Products/Debug/ProxyTun.app"

echo "Building ProxyTun macOS Debug app..."
xcodebuild \
  -project "$PROJECT" \
  -scheme ProxyTun \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "Stopping existing ProxyTun process if needed..."
pkill -x ProxyTun || true

echo "Launching app..."
open "$APP_PATH"

echo "Waiting for process..."
sleep 2
pgrep -fl 'ProxyTun.app/Contents/MacOS/ProxyTun|ProxyTun$' || true

echo "Done."
echo "App path: $APP_PATH"

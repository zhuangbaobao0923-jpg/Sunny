#!/bin/bash
# 一键在 iPhone 模拟器里运行心屿 App
# 用法：bash ~/Documents/newproject/MBTIRoleplay/run-ios.sh

set -e
cd "$(dirname "$0")"

DEVICE_NAME="iPhone 18 Pro"
BUNDLE_ID="com.example.MBTIRoleplay"

echo "=== 1/4 编译 ==="
xcodebuild -project MBTIRoleplay.xcodeproj \
  -scheme MBTIRoleplay \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -derivedDataPath ./build \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -3

APP_PATH="build/Build/Products/Debug-iphonesimulator/MBTIRoleplay.app"
if [ ! -d "$APP_PATH" ]; then
  echo "✗ 没有找到编译产物：$APP_PATH"
  exit 1
fi

echo ""
echo "=== 2/4 启动模拟器 ==="
BOOTED=$(xcrun simctl list devices booted | grep -c "$DEVICE_NAME" || true)
if [ "$BOOTED" -eq 0 ]; then
  open -a Simulator
  xcrun simctl boot "$DEVICE_NAME" 2>/dev/null || true
  sleep 3
fi

echo ""
echo "=== 3/4 安装 App ==="
xcrun simctl install booted "$APP_PATH"

echo ""
echo "=== 4/4 启动 App ==="
xcrun simctl launch booted "$BUNDLE_ID"

echo ""
echo "✓ 完成，看模拟器窗口。"

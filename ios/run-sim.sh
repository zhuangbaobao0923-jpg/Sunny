#!/usr/bin/env bash
# 「夜谈」一键跑模拟器：编译 → 启动模拟器 → 安装 → 打开
# 用法：
#   bash ios/run-sim.sh                 # 自动挑一台可用 iPhone 模拟器
#   SIM_NAME="iPhone 16 Pro" bash ios/run-sim.sh
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")"

BUNDLE_ID="com.chat.zyq"
SIM_NAME="${SIM_NAME:-}"

echo "→ 正在挑选模拟器..."
UDID=$(/usr/bin/python3 - "$SIM_NAME" <<'PY'
import json, subprocess, sys
want = sys.argv[1].strip()
data = json.loads(subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                                 capture_output=True, text=True).stdout)
picked = None
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for dev in devices:
        if want and dev["name"] != want:
            continue
        if not want and "iPhone" not in dev["name"]:
            continue
        picked = (dev["name"], dev["udid"])
        break
    if picked:
        break
print(f"{picked[0]}|{picked[1]}" if picked else "|")
PY
)
SIM_TITLE="${UDID%%|*}"
SIM_UDID="${UDID##*|}"

if [[ -z "$SIM_UDID" ]]; then
  echo "✗ 没找到可用的 iPhone 模拟器（${SIM_NAME:-任意}）。已安装的模拟器："
  xcrun simctl list devices available | grep -E "iPhone|iOS" | head -12
  echo "  可先打开 Xcode → Settings → Components 下载一个 iOS 运行时。"
  exit 1
fi
echo "✓ 使用模拟器：$SIM_TITLE"

xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1 || true
open -a Simulator >/dev/null 2>&1 || open -a DeviceHub >/dev/null 2>&1 || true

echo "→ 编译（首次约 1-2 分钟）..."
LOG=$(mktemp -t nighttalk-build)
if ! xcodebuild build \
      -project AICompanion.xcodeproj \
      -scheme AICompanion \
      -configuration Debug \
      -destination "id=$SIM_UDID" \
      -derivedDataPath ./build-sim \
      OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' >"$LOG" 2>&1; then
  echo "✗ 编译失败："
  grep -E "error:" "$LOG" | head -10
  echo "  完整日志：$LOG"
  exit 1
fi

APP="./build-sim/Build/Products/Debug-iphonesimulator/AICompanion.app"
if [[ ! -d "$APP" ]]; then
  echo "✗ 编译产物不存在：$APP"
  exit 1
fi

echo "→ 安装并启动..."
xcrun simctl install "$SIM_UDID" "$APP"
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" >/dev/null
echo ""
echo "✓ 已在 $SIM_TITLE 启动「夜谈」。"
echo "  提示：不填密钥也能跑（聊天走本地人设、语音用系统音色）；"
echo "       想接真模型见 README「接入真实模型」一节。"

#!/usr/bin/env bash
# 「夜谈」一键装真机：自动找连接的 iPhone → 编译 → 安装 → 启动
# 前置：手机已连数据线并信任此电脑；Xcode 已登录 Apple ID 并设好 Team
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")"

BUNDLE_ID="com.chat.zyq"
JSON=$(mktemp -t devlist)

echo "→ 正在检测连接的 iPhone..."
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true

UDID=$(/usr/bin/python3 - "$JSON" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
devices = data.get("result", {}).get("devices", [])
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("reality") == "simulated":
        continue
    # 只认 iOS 真机（Mac 会带自己的 UDID 出现在列表里）
    if hw.get("platform", "").lower() != "ios" and not str(hw.get("productType", "")).startswith("iPhone"):
        continue
    udid = hw.get("udid")
    if udid:
        print(udid)
        break
PY
)

if [[ -z "${UDID:-}" ]]; then
  echo ""
  echo "✗ 没有找到已连接的 iPhone。请依次检查："
  echo "  1. 数据线是否支持数据传输（很多线只能充电）"
  echo "  2. 手机是否弹窗并点了「信任」"
  echo "  3. 尽量直插 Mac 接口，不要经过扩展坞 / USB Hub"
  echo "  4. 手机上：设置 → 隐私与安全性 → 开发者模式 是否已打开"
  exit 1
fi

echo "✓ 找到设备：$UDID"

# ---------- 证书续签守护 ----------
# 免费开发者证书只有 7 天有效期。更坑的是：Xcode 会复用本地缓存的旧描述文件，
# 导致「编译、安装都成功，但一点图标就提示『不再可用』」。
# 这里在构建前检查缓存描述文件剩余天数，低于 2 天就删掉，逼 Xcode 重新签发。
PROF_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
/usr/bin/python3 - "$PROF_DIR" "$BUNDLE_ID" <<'PY' || true
import glob, os, sys, subprocess, plistlib, datetime
prof_dir, bundle_id = sys.argv[1], sys.argv[2]
if not os.path.isdir(prof_dir):
    sys.exit(0)
now = datetime.datetime.now(datetime.timezone.utc)
for f in glob.glob(os.path.join(prof_dir, "*.mobileprovision")):
    try:
        raw = subprocess.run(["security", "cms", "-D", "-i", f],
                             capture_output=True, check=True).stdout
        pl = plistlib.loads(raw)
        if bundle_id not in pl.get("Name", ""):
            continue
        exp = pl.get("ExpirationDate")
        if exp is None:
            continue
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=datetime.timezone.utc)
        days = (exp - now).total_seconds() / 86400
        local = exp.astimezone().strftime("%Y-%m-%d %H:%M")
        if days < 2:
            os.remove(f)
            print(f"⚠️  描述文件仅剩 {days:.1f} 天（{local} 到期），已清除缓存，本次将重新签发")
        else:
            print(f"✓ 描述文件有效，剩余 {days:.1f} 天（{local} 到期）")
    except Exception:
        pass
PY

echo "→ 开始编译（首次会自动申请签名证书，可能需要 1-2 分钟）..."

BUILD_LOG=$(xcodebuild build \
  -project AICompanion.xcodeproj \
  -scheme AICompanion \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath ./build \
  -allowProvisioningUpdates \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' \
  2>&1) || true

echo "$BUILD_LOG" | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true

# 构建失败时绝不继续安装：否则会把上一次的旧包装上去，看起来「装好了」其实是旧代码
if ! echo "$BUILD_LOG" | grep -q "BUILD SUCCEEDED"; then
  echo ""
  echo "✗ 编译失败，已终止安装（刚才没有安装任何东西）"
  echo "  常见原因：Xcode 里 Apple ID 掉线 / 描述文件过期 →"
  echo "  打开 Xcode → Settings → Accounts 重新登录，再跑一次本脚本"
  exit 1
fi

APP="./build/Build/Products/Debug-iphoneos/AICompanion.app"
if [[ ! -d "$APP" ]]; then
  echo "✗ 编译产物不存在，请查看上面的报错"
  exit 1
fi

echo "→ 安装到手机..."
xcrun devicectl device install app --device "$UDID" "$APP"

echo "→ 启动 App..."
LAUNCH_LOG=$(mktemp -t launchlog)
if xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" --terminate-existing >"$LAUNCH_LOG" 2>&1; then
  echo ""
  echo "✓ 完成，App 已启动。"
  exit 0
fi

if grep -q "not been explicitly trusted\|invalid code signature" "$LAUNCH_LOG"; then
  echo ""
  echo "⚠️  安装成功，但 iOS 需要你手动信任一次开发者证书："
  echo "   1. 手机「设置」→「通用」→「VPN与设备管理」"
  echo "   2. 在「开发者 App」下点「Apple Development: 8615629881309」"
  echo "   3. 点「信任」→ 再点一次「信任」"
  echo "   4. 回桌面点「夜谈」图标"
  echo ""
  echo "   注意：不要卸载 App，卸载会清空聊天记录。信任一次即可。"
  exit 0
fi

echo ""
echo "⚠️  启动请求被拒绝，原始信息："
tail -6 "$LAUNCH_LOG"
echo "   若手机处于锁屏状态，请解锁后重试。"

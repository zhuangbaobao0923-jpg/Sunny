#!/bin/bash
# Xcode 安装后的一键初始化脚本
# 用法：等 App Store 里 Xcode 下载安装完成后，在「终端」里执行：
#   bash ~/Documents/newproject/setup-xcode.sh
# 过程中会要求输入一次开机密码（sudo 需要）。

set -e

XCODE_APP="/Applications/Xcode.app"

echo "=== 1/4 检查 Xcode.app 是否存在 ==="
if [ ! -d "$XCODE_APP" ]; then
  echo "✗ 没有找到 $XCODE_APP"
  echo "  请先在 App Store 里完成 Xcode 的下载安装，再重新运行本脚本。"
  exit 1
fi
echo "✓ 已找到 Xcode.app"

echo ""
echo "=== 2/4 切换命令行工具链到 Xcode ==="
sudo xcode-select -s "$XCODE_APP/Contents/Developer"
echo "✓ 当前路径：$(xcode-select -p)"

echo ""
echo "=== 3/4 同意许可协议 + 安装首次启动组件 ==="
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
echo "✓ 组件安装完成"

echo ""
echo "=== 4/4 验证并打开模拟器 ==="
xcodebuild -version
echo ""
echo "✓ 全部完成，正在启动 iPhone 模拟器..."
open -a Simulator

echo ""
echo "接下来可以回到对话里告诉我「装好了」，我来生成 SwiftUI 工程。"

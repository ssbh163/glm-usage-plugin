#!/bin/bash
# ============================================================================
# 文件作用：把 ZCodeUsageHUD.swift 编译并打包成 macOS 应用包 ZCodeUsageHUD.app
#
# 为什么这样做：
#   - 打成 .app 才能设置 LSUIElement=true（不占 Dock、不抢焦点）
#   - 打成 .app 才能用 `open -g` 做「已运行则唤出」的幂等启动
#   - ad-hoc 签名让应用有稳定身份，避免每次重建后系统重复询问权限
#
# 用法：bash ~/.zcode/zcode-usage-hud/build.sh
# ============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$DIR/ZCodeUsageHUD.app"
NAME="ZCodeUsageHUD"

echo "==> 清理旧的应用包"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 Swift 源码"
swiftc -O -swift-version 5 \
  -framework AppKit -framework Carbon \
  "$DIR/$NAME.swift" \
  -o "$APP/Contents/MacOS/$NAME"

echo "==> 写入 Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ZCodeUsageHUD</string>
    <key>CFBundleIdentifier</key>
    <string>com.wangzhe.zcodeusagehud</string>
    <key>CFBundleName</key>
    <string>GLM 用量</string>
    <key>CFBundleDisplayName</key>
    <string>GLM 用量悬浮窗</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "   （签名失败，不影响本机运行）"

echo "==> 完成：$APP"

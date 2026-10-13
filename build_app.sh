#!/bin/bash
# SuperState 一键打包脚本：
#   swift build release -> 构建 SuperState.app -> ad-hoc 签名 -> 输出到 产品 目录
set -e
cd "$(dirname "$0")"

APP_NAME="SuperState"
PRODUCT_DIR="$(cd ../../产品 && pwd)"
APP="$PRODUCT_DIR/$APP_NAME.app"

echo "==> [1/4] Release 编译..."
# --disable-sandbox：本机环境 sandbox_apply 不可用，SwiftPM 内置沙箱会报
# "sandbox-exec: sandbox_apply: Operation not permitted"，需显式关闭
# BUILD_DIR 可指定备用构建目录（增量缓存损坏时用，避免删 .build）
BUILD_DIR="${BUILD_DIR:-.build}"
swift build -c release --disable-sandbox --build-path "$BUILD_DIR"

BIN="$BUILD_DIR/x86_64-apple-macosx/release/$APP_NAME"
if [ ! -f "$BIN" ]; then
  BIN="$(find "$BUILD_DIR" -type f -name "$APP_NAME" -path "*release*" | head -1)"
fi

echo "==> [2/4] 构建 App Bundle..."
# 每次都强制重建 kext（避免旧二进制残留导致打进错误的驱动）
if [ -f "Kext/build_kext.sh" ]; then
  rm -rf "Kext/SuperStateKext.kext"
  (cd Kext && ./build_kext.sh) >/dev/null 2>&1 || echo "  警告：kext 构建失败（可稍后在 Kext 目录手动执行 build_kext.sh）"
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP/Contents/Info.plist"

# 管理员模式启动脚本（setsid 常驻 powermetrics）
if [ -f "Assets/superstate_start.sh" ]; then
  cp "Assets/superstate_start.sh" "$APP/Contents/Resources/superstate_start.sh"
  chmod +x "$APP/Contents/Resources/superstate_start.sh"
fi

# 硬件监控驱动 kext + 安装/卸载脚本（一次性授权后免密码读实时频率/各域功率）
if [ -d "Kext/SuperStateKext.kext" ]; then
  cp -R "Kext/SuperStateKext.kext" "$APP/Contents/Resources/"
  for s in install_kext.sh uninstall_kext.sh; do
    if [ -f "Kext/$s" ]; then
      cp "Kext/$s" "$APP/Contents/Resources/$s"
      chmod +x "$APP/Contents/Resources/$s"
    fi
  done
fi

# 图标（如存在）
if [ -f "Assets/icon_1024.png" ]; then
  rm -rf /tmp/ss.iconset
  mkdir -p /tmp/ss.iconset
  sips -z 16 16 Assets/icon_1024.png --out /tmp/ss.iconset/icon_16x16.png >/dev/null 2>&1
  sips -z 32 32 Assets/icon_1024.png --out /tmp/ss.iconset/icon_16x16@2x.png >/dev/null 2>&1
  sips -z 32 32 Assets/icon_1024.png --out /tmp/ss.iconset/icon_32x32.png >/dev/null 2>&1
  sips -z 64 64 Assets/icon_1024.png --out /tmp/ss.iconset/icon_32x32@2x.png >/dev/null 2>&1
  sips -z 128 128 Assets/icon_1024.png --out /tmp/ss.iconset/icon_128x128.png >/dev/null 2>&1
  sips -z 256 256 Assets/icon_1024.png --out /tmp/ss.iconset/icon_128x128@2x.png >/dev/null 2>&1
  sips -z 256 256 Assets/icon_1024.png --out /tmp/ss.iconset/icon_256x256.png >/dev/null 2>&1
  sips -z 512 512 Assets/icon_1024.png --out /tmp/ss.iconset/icon_256x256@2x.png >/dev/null 2>&1
  sips -z 512 512 Assets/icon_1024.png --out /tmp/ss.iconset/icon_512x512.png >/dev/null 2>&1
  cp Assets/icon_1024.png /tmp/ss.iconset/icon_512x512@2x.png
  iconutil -c icns /tmp/ss.iconset -o "$APP/Contents/Resources/$APP_NAME.icns"
  rm -rf /tmp/ss.iconset
fi

echo "==> [3/4] ad-hoc 签名..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

echo "==> [4/5] 完成 App"
echo "产物: $APP"

echo "==> [5/5] 制作 DMG 安装器..."
STAGE="/tmp/${APP_NAME}_dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# 卷图标（App 图标作为 DMG 外观）
if [ -f "$APP/Contents/Resources/$APP_NAME.icns" ]; then
  cp "$APP/Contents/Resources/$APP_NAME.icns" "$STAGE/.VolumeIcon.icns"
fi
# 生成"拖动到应用程序"背景图
BG_OK=0
if [ -f "Assets/make_dmg_bg.swift" ] && [ -f "Assets/icon_1024.png" ]; then
  if swiftc -O -o /tmp/make_dmg_bg Assets/make_dmg_bg.swift 2>/dev/null; then
    if /tmp/make_dmg_bg "Assets/icon_1024.png" "$STAGE/.background/bg.png"; then
      BG_OK=1
    fi
  fi
fi

DMG="$PRODUCT_DIR/$APP_NAME.dmg"
rm -f "$DMG"

# 优先 dmgbuild（Python，直接写 .DS_Store 布局，无需 Finder 自动化权限）：
# 窗口背景"拖动到应用程序"提示图 + 图标定位 + App 图标作卷宗图标
PYENV="/Users/beimo/.workbuddy/binaries/python/envs/default/bin/python3"
DMGBUILD_OK=0
if [ "$BG_OK" = "1" ] && [ -x "$PYENV" ] && "$PYENV" -c "import dmgbuild" 2>/dev/null; then
  hdiutil detach "/Volumes/$APP_NAME" -force -quiet 2>/dev/null || true
  # 生成带绝对路径的 dmgbuild 配置（-D 只支持字符串，列表需直接写文件）
  SETTINGS="/tmp/ss_dmg_settings.py"
  cat > "$SETTINGS" <<PYEOF
volume_name = "$APP_NAME"
format = "UDZO"
files = [r"$APP"]
symlinks = {"Applications": "/Applications"}
icon_size = 128
window_rect = ((400, 100), (660, 420))
background = r"$STAGE/.background/bg.png"
icon_locations = {"$APP_NAME.app": (110, 116), "Applications": (422, 116)}
volume_icon = r"$APP/Contents/Resources/$APP_NAME.icns"
show_status_bar = False
show_toolbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
PYEOF
  if "$PYENV" -m dmgbuild -s "$SETTINGS" "$APP_NAME" "$DMG" >/tmp/ss_dmgbuild.log 2>&1; then
    DMGBUILD_OK=1
    # dmgbuild 不实现卷宗图标：转回 RW 写入 .VolumeIcon.icns + 自定义图标位，再压回 UDZO
    VI_RW="/tmp/ss_volicon_rw.dmg"
    rm -f "$VI_RW"
    if hdiutil convert "$DMG" -format UDRW -ov -o "$VI_RW" >/dev/null 2>&1; then
      hdiutil detach "/Volumes/$APP_NAME" -force -quiet 2>/dev/null || true
      if hdiutil attach -readwrite -nobrowse -noverify "$VI_RW" >/dev/null 2>&1; then
        cp "$APP/Contents/Resources/$APP_NAME.icns" "/Volumes/$APP_NAME/.VolumeIcon.icns" 2>/dev/null || true
        /usr/bin/SetFile -a C "/Volumes/$APP_NAME" 2>/dev/null || true
        sync
        for i in 1 2 3; do
          hdiutil detach "/Volumes/$APP_NAME" -quiet 2>/dev/null && break
          sleep 1
          hdiutil detach "/Volumes/$APP_NAME" -force -quiet 2>/dev/null && break
        done
        hdiutil convert "$VI_RW" -format UDZO -ov -o "$DMG" >/dev/null 2>&1 || true
      fi
      rm -f "$VI_RW"
    fi
  else
    tail -3 /tmp/ss_dmgbuild.log
  fi
fi
rm -rf "$STAGE"

if [ "$DMGBUILD_OK" = "1" ]; then
  echo "DMG: $DMG"
else
  # 回退：直出 DMG（无窗口布局，仅 Applications 快捷方式 + 卷图标文件）
  STAGE2="/tmp/${APP_NAME}_dmg2"
  rm -rf "$STAGE2"; mkdir -p "$STAGE2"
  cp -R "$APP" "$STAGE2/"
  ln -s /Applications "$STAGE2/Applications"
  [ -f "$APP/Contents/Resources/$APP_NAME.icns" ] && cp "$APP/Contents/Resources/$APP_NAME.icns" "$STAGE2/.VolumeIcon.icns"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE2" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE2"
  echo "DMG（简化布局）: $DMG"
fi

open "$PRODUCT_DIR"

#!/bin/bash
# SuperStateKext 卸载脚本（需一次性管理员授权）：卸载内核扩展 + 清理安装文件与开机自载服务
set -e
DEST="/Library/Extensions/SuperStateKext.kext"
DAEMON="/Library/LaunchDaemons/com.superstate.kextload.plist"

echo "==> 卸载内核扩展"
kmutil unload -p "$DEST" 2>/dev/null || true

echo "==> 删除驱动文件与开机自载服务"
rm -rf "$DEST"
rm -f "$DAEMON"

echo "==> 卸载完成"

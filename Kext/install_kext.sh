#!/bin/bash
# SuperStateKext 安装脚本（需一次性管理员授权）
# 安全顺序（最高优先级 = 不弄坏系统）：
#   1) 先卸载可能正在运行的内核扩展（含旧版本），确保无用户客户端占用、无已加载镜像；
#   2) 再删除旧副本；3) 拷入新版；4) 加载新版；5) 注册开机自加载。
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
KEXT="$SRC/SuperStateKext.kext"
DEST="/Library/Extensions/SuperStateKext.kext"
DAEMON="/Library/LaunchDaemons/com.superstate.kextload.plist"

[ -d "$KEXT" ] || { echo "找不到 $KEXT"; exit 1; }

echo "==> 先卸载可能正在运行（含旧版本）的内核扩展"
# 先按路径卸载（旧副本仍在磁盘上，路径有效），再按 bundle-id 兜底
kmutil unload -p "$DEST" 2>/dev/null || true
kmutil unload -b com.superstate.kext 2>/dev/null || true

echo "==> 删除已安装副本"
rm -rf "$DEST"

echo "==> 安装到 $DEST"
cp -R "$KEXT" "$DEST"
chown -R root:wheel "$DEST"
chmod -R 755 "$DEST"

echo "==> 重建扩展集合并加载新版"
kmutil load -p "$DEST"

echo "==> 安装开机自加载服务"
cat > "$DAEMON" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.superstate.kextload</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/kmutil</string>
		<string>load</string>
		<string>-p</string>
		<string>/Library/Extensions/SuperStateKext.kext</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
</dict>
</plist>
PLIST
chown root:wheel "$DAEMON"
chmod 644 "$DAEMON"

echo "==> 完成"
kmutil showloaded 2>/dev/null | grep -i superstate && echo "内核扩展已加载" || echo "内核扩展加载状态待确认（kextstat 检查）"

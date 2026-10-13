#!/bin/bash
# SuperStateKext 安装脚本（需一次性管理员授权）
# 1) 拷贝到 /Library/Extensions 2) 加载进内核 3) 安装开机自加载 LaunchDaemon
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
KEXT="$SRC/SuperStateKext.kext"
DEST="/Library/Extensions/SuperStateKext.kext"
DAEMON="/Library/LaunchDaemons/com.superstate.kextload.plist"

[ -d "$KEXT" ] || { echo "找不到 $KEXT"; exit 1; }

echo "==> 安装到 $DEST"
rm -rf "$DEST"
cp -R "$KEXT" "$DEST"
chown -R root:wheel "$DEST"
chmod -R 755 "$DEST"

echo "==> 加载内核扩展"
# 先卸载旧版本（如存在）
kmutil unload -p "$DEST" 2>/dev/null || true
# 重建扩展集合并加载
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

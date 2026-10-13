import Foundation
import AppKit
import SwiftUI

/// 快捷工具：清空废纸篓、开机自启、常用 App 启动、网速悬浮窗
enum QuickActions {

    // MARK: - 清空废纸篓

    static func emptyTrash(completion: @escaping (Bool, String?) -> Void) {
        let script = """
        tell application "Finder" to empty trash
        """
        runAppleScript(script, completion: completion)
    }

    // MARK: - 开机自启（LaunchAgent）

    static var launchAtLogin: Bool {
        get { FileManager.default.fileExists(atPath: agentPlistPath) }
        set {
            if newValue { installLaunchAgent() } else { removeLaunchAgent() }
        }
    }

    private static var agentPlistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/com.superstate.app.plist"
    }

    private static func installLaunchAgent() {
        let execPath = Bundle.main.executablePath ?? "/usr/bin/true"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.superstate.app</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(execPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        do {
            try plist.write(toFile: agentPlistPath, atomically: true, encoding: .utf8)
        } catch {
            NSLog("SuperState: 写入 LaunchAgent 失败 \(error)")
        }
    }

    private static func removeLaunchAgent() {
        try? FileManager.default.removeItem(atPath: agentPlistPath)
    }

    // MARK: - 常用 App 快速启动

    static func installedApplications() -> [URL] {
        var urls: [URL] = []
        for dir in ["/Applications", "\(NSHomeDirectory())/Applications"] {
            if let apps = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) {
                urls.append(contentsOf: apps.filter { $0.pathExtension == "app" })
            }
        }
        return urls.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    @discardableResult
    static func openApplication(_ url: URL) -> Bool {
        let conf = NSWorkspace.OpenConfiguration()
        conf.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: conf) { _, _ in }
        return true
    }

    // MARK: - AppleScript 辅助

    private static func runAppleScript(_ source: String, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = false
            var message: String?
            if let osa = NSAppleScript(source: source) {
                var errorInfo: NSDictionary?
                osa.executeAndReturnError(&errorInfo)
                if let err = errorInfo {
                    message = (err[NSAppleScript.errorMessage] as? String) ?? "执行失败"
                } else {
                    ok = true
                }
            } else {
                message = "AppleScript 创建失败"
            }
            // 回调统一回主队列：调用方多在 SwiftUI 环境中更新 @State
            DispatchQueue.main.async { completion(ok, message) }
        }
    }
}

// MARK: - 网速悬浮窗

final class FloatingWindowController: NSWindowController, NSWindowDelegate {

    static let shared = FloatingWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 54),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: NetFloatingView())
        position()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        window?.setFrameOrigin(NSPoint(x: frame.maxX - 240, y: frame.maxY - 120))
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        guard let w = window else { return }
        if w.isVisible {
            w.orderOut(nil)
        } else {
            position()
            w.orderFrontRegardless()
        }
    }
}

/// 悬浮窗内容：实时上下行速率
struct NetFloatingView: View {
    @ObservedObject var monitor = Monitor.shared

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Label(String(format: "↑ %@", Format.rate(monitor.snapshot.netUpBytesPerSec)), systemImage: "arrow.up")
                Label(String(format: "↓ %@", Format.rate(monitor.snapshot.netDownBytesPerSec)), systemImage: "arrow.down")
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            Label(String(format: "CPU %.0f%% · 内存 %.0f%%", monitor.snapshot.cpuUsage, monitor.snapshot.memUsedPercent), systemImage: "gauge")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(4)
    }
}

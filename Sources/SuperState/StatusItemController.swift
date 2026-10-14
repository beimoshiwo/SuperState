import AppKit
import SwiftUI

/// 菜单栏状态项：上下排版（数值在上、标签在下），点击弹出状态面板
final class StatusItemController: NSObject {

    static let shared = StatusItemController()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var barHost: NSHostingView<MenuBarStack>!
    private let monitor = Monitor.shared

    private override init() {}

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // 自定义上下排版视图，替代纯文字 title
        let host = NSHostingView(rootView: MenuBarStack(items: []))
        host.autoresizingMask = []
        button.addSubview(host)
        barHost = host
        button.title = ""

        buildMenu()

        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: PanelView())
        pop.contentSize = NSSize(width: 460, height: 640)
        popover = pop

        updateTitle()
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateTitle), userInfo: nil, repeats: true)
    }

    // MARK: - 菜单栏内容

    @objc private func updateTitle() {
        let items = buildItems(monitor.snapshot)
        barHost.rootView = MenuBarStack(items: items)
        barHost.needsLayout = true
        barHost.layoutSubtreeIfNeeded()

        let fit = barHost.fittingSize
        let w = max(1, ceil(fit.width))
        statusItem.length = w + 4
        if let button = statusItem.button {
            barHost.frame = CGRect(x: 2, y: 0, width: w, height: button.bounds.height)
        }
    }

    /// 生成上下排版的列：每列 value(上) + label(下)
    private func buildItems(_ s: SystemSnapshot) -> [BarItem] {
        let igpu = s.gpus.first(where: { $0.isIntegrated })
        let dgpu = s.gpus.first(where: { !$0.isIntegrated })
        var items: [BarItem] = []

        if Settings.barShowCPU {
            items.append(BarItem(id: "cpu", value: String(format: "%.0f%%", s.cpuUsage), label: "CPU"))
        }
        if Settings.barShowCPUTemp {
            items.append(BarItem(id: "cputemp",
                                 value: s.cpuTempC.map { String(format: "%.0f°", $0) } ?? "–", label: "温度"))
        }
        if Settings.barShowCPUFreq {
            items.append(BarItem(id: "cpufreq",
                                 value: s.cpuFreqMhz.map { String(format: "%.2fG", $0 / 1000) } ?? "–", label: "频率"))
        }
        if Settings.barShowPackagePower {
            items.append(BarItem(id: "pkgpow",
                                 value: s.packagePowerWatts.map { Format.power($0) } ?? "–",
                                 label: "英特尔整机"))
        }
        if Settings.barShowTotalPower {
            items.append(BarItem(id: "totalpow",
                                 value: s.totalPowerWatts.map { Format.power($0) } ?? "–",
                                 label: "整机"))
        }
        if Settings.barShowCPUPower {
            items.append(BarItem(id: "cpupow",
                                 value: s.cpuPowerWatts.map { Format.power($0) } ?? "–",
                                 label: "CPU功耗"))
        }
        if Settings.barShowMem {
            items.append(BarItem(id: "mem", value: String(format: "%.0f%%", s.memUsedPercent), label: "内存"))
        }
        if Settings.barShowMemPressure {
            items.append(BarItem(id: "memp", value: String(format: "%.0f%%", s.memPressurePercent), label: "压力"))
        }
        if Settings.barShowProcess {
            items.append(BarItem(id: "proc", value: "\(s.processCount)", label: "进程"))
        }
        if Settings.barShowThread {
            items.append(BarItem(id: "thr", value: s.threadCount > 0 ? "\(s.threadCount)" : "–", label: "线程"))
        }
        if Settings.barShowFile {
            items.append(BarItem(id: "file", value: s.fileCount > 0 ? "\(s.fileCount)" : "–", label: "句柄"))
        }
        if let d = dgpu {
            if Settings.barShowDGPU {
                items.append(BarItem(id: "dgpu", value: String(format: "%.0f%%", d.utilization), label: d.shortModel))
            }
            if Settings.barShowDGPUTemp {
                items.append(BarItem(id: "dgt", value: d.temperatureC.map { String(format: "%.0f°", $0) } ?? "–", label: "独显温"))
            }
            if Settings.barShowDGPUFreq {
                items.append(BarItem(id: "dgfreq", value: d.freqText, label: d.shortModel))
            }
            if Settings.barShowDGPUPower {
                items.append(BarItem(id: "dgpow",
                                     value: d.powerWatts.map { Format.power($0) } ?? "–", label: "独显功耗"))
            }
            if Settings.barShowVRAM, d.vramTotalBytes > 0 {
                items.append(BarItem(id: "vram", value: String(format: "%.0f", d.vramUsedMB), label: "显存"))
            }
        }
        if let i = igpu {
            if Settings.barShowIGPU {
                items.append(BarItem(id: "igpu", value: String(format: "%.0f%%", i.utilization), label: i.shortModel))
            }
            if Settings.barShowIGPUTemp {
                items.append(BarItem(id: "igt", value: i.temperatureC.map { String(format: "%.0f°", $0) } ?? "–", label: "核显温"))
            }
            if Settings.barShowIGPUFreq {
                items.append(BarItem(id: "igfreq", value: i.freqText, label: i.shortModel))
            }
            if Settings.barShowIGPUPower {
                items.append(BarItem(id: "igpow",
                                     value: i.powerWatts.map { Format.power($0) } ?? "–", label: "核显功耗"))
            }
        }
        if Settings.barShowFans, let f0 = s.fans.first {
            items.append(BarItem(id: "fan", value: String(format: "%.0f", f0.rpm), label: "风扇"))
        }
        if Settings.barShowBattery {
            items.append(BarItem(id: "bat", value: s.batteryTempC.map { String(format: "%.0f°", $0) } ?? "–", label: "电池"))
        }
        if Settings.barShowDisk {
            items.append(BarItem(id: "disk", value: String(format: "%.0f%%", s.diskUsedPercent), label: "磁盘"))
        }
        if Settings.barShowNet {
            items.append(BarItem(id: "up", value: Settings.compactRate(s.netUpBytesPerSec), label: "上行"))
            items.append(BarItem(id: "down", value: Settings.compactRate(s.netDownBytesPerSec), label: "下行"))
        }
        return items
    }

    // MARK: - 点击

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        } else {
            togglePopover(sender)
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 供全局热键调用：切换状态面板显示/隐藏
    func togglePanelFromHotkey() {
        togglePopover(nil)
    }

    // MARK: - 菜单

    private func buildMenu() {
        let menu = NSMenu()

        let main = NSMenuItem(title: "打开主界面…", action: #selector(showMain), keyEquivalent: "m")
        main.target = self
        menu.addItem(main)

        let panel = NSMenuItem(title: "状态面板", action: #selector(togglePopover(_:)), keyEquivalent: "")
        panel.target = self
        menu.addItem(panel)

        let float = NSMenuItem(title: "网速悬浮窗", action: #selector(toggleFloat), keyEquivalent: "")
        float.target = self
        menu.addItem(float)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "开机自动启动", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = QuickActions.launchAtLogin ? .on : .off
        menu.addItem(login)

        let admin = NSMenuItem(title: "管理员模式（实时 CPU 频率）", action: #selector(toggleAdmin), keyEquivalent: "")
        admin.target = self
        admin.state = ThermalMetrics.shared.adminEnabled ? .on : .off
        menu.addItem(admin)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 SuperState", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func showMain() {
        MainWindowController.shared.show()
    }

    @objc private func toggleFloat() {
        FloatingWindowController.shared.toggle()
    }

    @objc private func toggleLogin() {
        QuickActions.launchAtLogin.toggle()
        buildMenu()
    }

    @objc private func toggleAdmin() {
        if ThermalMetrics.shared.adminEnabled {
            ThermalMetrics.shared.disable { [weak self] _, _ in
                DispatchQueue.main.async { self?.buildMenu() }
            }
        } else {
            ThermalMetrics.shared.enable { [weak self] ok, _ in
                DispatchQueue.main.async { self?.buildMenu() }
            }
        }
    }

    @objc private func quit() {
        ThermalMetrics.shared.disable { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

// MARK: - 菜单栏上下排版视图

struct BarItem: Identifiable {
    let id: String
    let value: String
    let label: String
}

struct MenuBarStack: View {
    var items: [BarItem]

    var body: some View {
        HStack(spacing: 8) {
            // 小图标
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 10))
                .foregroundStyle(.primary)
            ForEach(items) { item in
                VStack(spacing: 1) {
                    Text(item.value)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Text(item.label)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .frame(minWidth: 24)
            }
        }
        .padding(.horizontal, 2)
    }
}

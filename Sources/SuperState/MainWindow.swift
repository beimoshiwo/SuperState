import AppKit
import SwiftUI

// MARK: - 主程序窗口

final class MainWindowController: NSWindowController {

    static let shared = MainWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SuperState 主界面"
        window.minSize = NSSize(width: 680, height: 600)
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let w = window else { return }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 主界面（TabView：仪表盘 / 监控项目 / 告警 / 工具）

struct SettingsView: View {
    @ObservedObject var monitor = Monitor.shared

    // 菜单栏显示项
    @State private var barCPU = Settings.barShowCPU
    @State private var barCPUTemp = Settings.barShowCPUTemp
    @State private var barCPUFreq = Settings.barShowCPUFreq
    @State private var barIGPUFreq = Settings.barShowIGPUFreq
    @State private var barDGPUFreq = Settings.barShowDGPUFreq
    @State private var barCPUPower = Settings.barShowCPUPower
    @State private var barPkgPower = Settings.barShowPackagePower
    @State private var barTotalPower = Settings.barShowTotalPower
    @State private var barMem = Settings.barShowMem
    @State private var barMemPressure = Settings.barShowMemPressure
    @State private var barProcess = Settings.barShowProcess
    @State private var barThread = Settings.barShowThread
    @State private var barFile = Settings.barShowFile
    @State private var barDGPU = Settings.barShowDGPU
    @State private var barIGPU = Settings.barShowIGPU
    @State private var barDGPUTemp = Settings.barShowDGPUTemp
    @State private var barIGPUTemp = Settings.barShowIGPUTemp
    @State private var barDGPUPower = Settings.barShowDGPUPower
    @State private var barIGPUPower = Settings.barShowIGPUPower
    @State private var barVRAM = Settings.barShowVRAM
    @State private var barFans = Settings.barShowFans
    @State private var barBattery = Settings.barShowBattery
    @State private var barNet = Settings.barShowNet
    @State private var barDisk = Settings.barShowDisk
    @State private var compact = Settings.compactBar
    /// 功率单位模式：0 自动 / 1 瓦 / 2 毫瓦
    @State private var powerUnitMode = Settings.powerUnitMode
    // 告警
    @State private var alertEnabled = Alerts.shared.enabled
    @State private var alertCPU = Alerts.shared.cpuThreshold
    @State private var alertMem = Alerts.shared.memThreshold
    @State private var alertGPUUtil = Alerts.shared.gpuUtilThreshold
    @State private var alertGPUTemp = Alerts.shared.gpuTempThreshold
    @State private var alertGPUPower = Alerts.shared.gpuPowerThreshold
    // 工具
    @State private var adminOn = ThermalMetrics.shared.adminEnabled
    @State private var launchOn = QuickActions.launchAtLogin
    // 当前标签页
    @State private var selectedTab = 0
    @State private var installing = false
    @State private var uninstalling = false
    @State private var installMsg = ""
    @State private var kextStatus: KextMetrics.Status = .notInstalled

    private var kextStatusIsOutdated: Bool {
        if case .outdated = kextStatus { return true }
        return false
    }

    private func refreshKextStatus() {
        kextStatus = KextMetrics.shared.status
    }

    private let tabs: [(id: Int, title: String, icon: String)] = [
        (0, "仪表盘", "gauge.with.dots.needle.67percent"),
        (1, "硬件参数", "cpu"),
        (7, "CPU-Z", "magnifyingglass"),
        (2, "监控项目", "list.bullet"),
        (3, "告警", "bell"),
                (4, "功能", "fanblades.fill"),
                (5, "工具", "wrench.and.screwdriver"),
                (6, "关于", "info.circle"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            // macOS 26 液态玻璃 Tab 栏（旧系统自动降级为毛玻璃）
            GlassTabBar(selection: $selectedTab, tabs: tabs)

            Group {
                switch selectedTab {
                case 1: HardwareView()
                case 7: CPUZView()
                case 2: monitorTab
                case 3: alertTab
                case 4: FeaturesView()
                case 5: toolsTab
                case 6: AboutView()
                default: DashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 600)
        .onAppear { syncAll(); refreshKextStatus() }
    }

    private func syncAll() {
        barCPU = Settings.barShowCPU; barCPUTemp = Settings.barShowCPUTemp
        barCPUFreq = Settings.barShowCPUFreq; barIGPUFreq = Settings.barShowIGPUFreq
        barDGPUFreq = Settings.barShowDGPUFreq
        barCPUPower = Settings.barShowCPUPower; barPkgPower = Settings.barShowPackagePower; barMem = Settings.barShowMem
        barTotalPower = Settings.barShowTotalPower
        barDGPUPower = Settings.barShowDGPUPower; barIGPUPower = Settings.barShowIGPUPower
        barMemPressure = Settings.barShowMemPressure
        barProcess = Settings.barShowProcess
        barThread = Settings.barShowThread
        barFile = Settings.barShowFile
        barDGPU = Settings.barShowDGPU; barIGPU = Settings.barShowIGPU
        barDGPUTemp = Settings.barShowDGPUTemp; barIGPUTemp = Settings.barShowIGPUTemp
        barVRAM = Settings.barShowVRAM; barFans = Settings.barShowFans
        barBattery = Settings.barShowBattery
        barNet = Settings.barShowNet; barDisk = Settings.barShowDisk
        compact = Settings.compactBar
        barDGPUPower = Settings.barShowDGPUPower; barIGPUPower = Settings.barShowIGPUPower
        powerUnitMode = Settings.powerUnitMode
        alertEnabled = Alerts.shared.enabled
        alertCPU = Alerts.shared.cpuThreshold; alertMem = Alerts.shared.memThreshold
        alertGPUUtil = Alerts.shared.gpuUtilThreshold; alertGPUTemp = Alerts.shared.gpuTempThreshold
        alertGPUPower = Alerts.shared.gpuPowerThreshold
        adminOn = ThermalMetrics.shared.adminEnabled
        launchOn = QuickActions.launchAtLogin
    }

    // MARK: 监控项目

    private var monitorTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("菜单栏显示", subtitle: "勾选要在菜单栏常驻显示的参数（温度/风扇/显存/功耗均免授权；⚠=实时频率需管理员模式）")

                Toggle("CPU 占用率", isOn: $barCPU).onChange(of: barCPU) { Settings.barShowCPU = $0 }
                Toggle("CPU 温度", isOn: $barCPUTemp).onChange(of: barCPUTemp) { Settings.barShowCPUTemp = $0 }
                Toggle("CPU 频率（标称免授权 / 实时需管理员）", isOn: $barCPUFreq).onChange(of: barCPUFreq) { Settings.barShowCPUFreq = $0 }
                Toggle("核显频率（部分平台提供；老硬件可能无数据）", isOn: $barIGPUFreq).onChange(of: barIGPUFreq) { Settings.barShowIGPUFreq = $0 }
                Toggle("独显频率（实时，免授权）", isOn: $barDGPUFreq).onChange(of: barDGPUFreq) { Settings.barShowDGPUFreq = $0 }
                Toggle("英特尔整机功耗监控（CPU+核显+SA，免授权）", isOn: $barPkgPower).onChange(of: barPkgPower) { Settings.barShowPackagePower = $0 }
                Toggle("真正的整机功耗（英特尔整机+独显，免授权）", isOn: $barTotalPower).onChange(of: barTotalPower) { Settings.barShowTotalPower = $0 }
                Toggle("CPU 功耗监控（CPU 核心功率，免授权）", isOn: $barCPUPower).onChange(of: barCPUPower) { Settings.barShowCPUPower = $0 }
                Toggle("内存占用率", isOn: $barMem).onChange(of: barMem) { Settings.barShowMem = $0 }
                Toggle("内存压力", isOn: $barMemPressure).onChange(of: barMemPressure) { Settings.barShowMemPressure = $0 }
                Toggle("进程数", isOn: $barProcess).onChange(of: barProcess) { Settings.barShowProcess = $0 }
                Toggle("线程数", isOn: $barThread).onChange(of: barThread) { Settings.barShowThread = $0 }
                Toggle("句柄数", isOn: $barFile).onChange(of: barFile) { Settings.barShowFile = $0 }
                Toggle("独显占用率", isOn: $barDGPU).onChange(of: barDGPU) { Settings.barShowDGPU = $0 }
                Toggle("核显占用率", isOn: $barIGPU).onChange(of: barIGPU) { Settings.barShowIGPU = $0 }
                Toggle("独显温度", isOn: $barDGPUTemp).onChange(of: barDGPUTemp) { Settings.barShowDGPUTemp = $0 }
                Toggle("核显温度", isOn: $barIGPUTemp).onChange(of: barIGPUTemp) { Settings.barShowIGPUTemp = $0 }
                Toggle("独显功耗（导轨实测，免授权）", isOn: $barDGPUPower).onChange(of: barDGPUPower) { Settings.barShowDGPUPower = $0 }
                Toggle("核显功耗（RAPL/SMC，免授权）", isOn: $barIGPUPower).onChange(of: barIGPUPower) { Settings.barShowIGPUPower = $0 }
                Toggle("独显显存占用", isOn: $barVRAM).onChange(of: barVRAM) { Settings.barShowVRAM = $0 }
                Toggle("风扇转速", isOn: $barFans).onChange(of: barFans) { Settings.barShowFans = $0 }
                Toggle("电池温度", isOn: $barBattery).onChange(of: barBattery) { Settings.barShowBattery = $0 }
                Toggle("网络上下行速率", isOn: $barNet).onChange(of: barNet) { Settings.barShowNet = $0 }
                Toggle("磁盘占用率", isOn: $barDisk).onChange(of: barDisk) { Settings.barShowDisk = $0 }
                Toggle("紧凑模式（更小的菜单栏文字）", isOn: $compact)
                    .onChange(of: compact) { Settings.compactBar = $0 }

                Divider().padding(.vertical, 4)

                Picker("功率单位", selection: $powerUnitMode) {
                    Text("自动（<1W 显示毫瓦）").tag(0)
                    Text("始终瓦（W）").tag(1)
                    Text("始终毫瓦（mW）").tag(2)
                }
                .onChange(of: powerUnitMode) { Settings.powerUnitMode = $0 }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("当前菜单栏效果预览").font(.caption).foregroundStyle(.secondary)
                    Text(barPreview).font(.system(size: 11, design: .monospaced))
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var barPreview: String {
        let s = monitor.snapshot
        let igpu = s.gpus.first(where: { $0.isIntegrated })
        let dgpu = s.gpus.first(where: { !$0.isIntegrated })
        let c = compact
        var parts: [String] = []
        if barCPU { parts.append(c ? String(format:"CPU%.0f%%", s.cpuUsage) : String(format:"CPU %.0f%%", s.cpuUsage)) }
        if barCPUTemp {
            parts.append(s.cpuTempC.map { c ? String(format:"CPU温%.0f°",$0) : String(format:"CPU温度 %.0f°C",$0) } ?? (c ? "CPU温–" : "CPU温度 –"))
        }
        if barCPUFreq {
            if let f = s.cpuFreqMhz {
                parts.append(c ? String(format:"CPU频%.2fG",f/1000) : String(format:"CPU频率 %.2fGHz",f/1000))
            } else { parts.append(c ? "CPU频–" : "CPU频率 –") }
        }
        if barIGPUFreq {
            parts.append(c ? "核显频\(igpu?.freqText ?? "待机")" : "核显频率 \(igpu?.freqText ?? "待机")")
        }
        if barDGPUFreq {
            parts.append(c ? "独显频\(dgpu?.freqText ?? "待机")" : "独显频率 \(dgpu?.freqText ?? "待机")")
        }
        if barDGPUPower {
            if let g = dgpu, let p = g.powerWatts {
                parts.append(c ? "独显功耗\(Format.power(p))" : "独显功耗 \(Format.power(p))")
            } else { parts.append(c ? "独显功耗–" : "独显功耗 –") }
        }
        if barIGPUPower {
            if let g = igpu, let p = g.powerWatts {
                parts.append(c ? "核显功耗\(Format.power(p))" : "核显功耗 \(Format.power(p))")
            } else { parts.append(c ? "核显功耗–" : "核显功耗 –") }
        }
        if barPkgPower {
            if let p = s.packagePowerWatts {
                parts.append(c ? "英特尔整机\(Format.power(p))" : "英特尔整机 \(Format.power(p))")
            } else { parts.append(c ? "英特尔整机–" : "英特尔整机 –") }
        }
        if barTotalPower {
            if let p = s.totalPowerWatts {
                parts.append(c ? "整机\(Format.power(p))" : "整机 \(Format.power(p))")
            } else { parts.append(c ? "整机–" : "整机 –") }
        }
        if barCPUPower {
            if let p = s.cpuPowerWatts {
                parts.append(c ? "CPU功耗\(Format.power(p))" : "CPU功耗 \(Format.power(p))")
            } else { parts.append(c ? "CPU功耗–" : "CPU功耗 –") }
        }
        if barMem { parts.append(c ? String(format:"内存%.0f%%",s.memUsedPercent) : String(format:"内存 %.0f%%",s.memUsedPercent)) }
        if barMemPressure { parts.append(c ? String(format:"压力%.0f%%",s.memPressurePercent) : String(format:"压力 %.0f%%",s.memPressurePercent)) }
        if barProcess { parts.append(c ? "进程\(s.processCount)" : "进程 \(s.processCount)") }
        if barThread { parts.append(c ? "线程\(s.threadCount)" : "线程 \(s.threadCount)") }
        if barFile { parts.append(c ? "句柄\(s.fileCount)" : "句柄 \(s.fileCount)") }
        if barDGPU, let g = dgpu { parts.append(c ? String(format:"%@ %.0f%%", g.shortModel, g.utilization) : String(format:"%@ %.0f%%", g.shortModel, g.utilization)) }
        if barIGPU, let g = igpu { parts.append(c ? String(format:"%@ %.0f%%", g.shortModel, g.utilization) : String(format:"%@ %.0f%%", g.shortModel, g.utilization)) }
        if barDGPUTemp {
            parts.append(dgpu?.temperatureC.map { c ? String(format:"独显温%.0f°",$0) : String(format:"独显温度 %.0f°C",$0) } ?? (c ? "独显温–" : "独显温度 –"))
        }
        if barIGPUTemp {
            parts.append(igpu?.temperatureC.map { c ? String(format:"核显温%.0f°",$0) : String(format:"核显温度 %.0f°C",$0) } ?? (c ? "核显温–" : "核显温度 –"))
        }
        if barVRAM, let g = dgpu, g.vramTotalBytes > 0 {
            parts.append(c ? String(format:"显存%.0f/%.0f", g.vramUsedMB, g.vramTotalMB)
                           : String(format:"显存 %.0f/%.0f MB", g.vramUsedMB, g.vramTotalMB))
        }
        if barFans {
            let vals = s.fans.map { String(format: "%.0f", $0.rpm) }.joined(separator: "/")
            parts.append(c ? "风扇\(vals)" : "风扇 \(vals) rpm")
        }
        if barBattery, let b = s.batteryTempC { parts.append(c ? String(format:"电池%.0f°",b) : String(format:"电池 %.0f°C",b)) }
        if barDisk { parts.append(c ? String(format:"磁盘%.0f%%",s.diskUsedPercent) : String(format:"磁盘 %.0f%%",s.diskUsedPercent)) }
        if barNet { parts.append("↑\(Settings.compactRate(s.netUpBytesPerSec)) ↓\(Settings.compactRate(s.netDownBytesPerSec))") }
        return parts.joined(separator: c ? " " : "  ")
    }

    // MARK: 告警

    private var alertTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("智能告警", subtitle: "指标超过阈值时发送系统通知（每分钟最多一次）")
                Toggle("启用告警", isOn: $alertEnabled).onChange(of: alertEnabled) { Alerts.shared.enabled = $0 }

                if alertEnabled {
                    thresholdRow("CPU 占用", value: $alertCPU, range: 50...99, unit: "%")
                        .onChange(of: alertCPU) { Alerts.shared.cpuThreshold = $0 }
                    thresholdRow("内存压力", value: $alertMem, range: 50...99, unit: "%")
                        .onChange(of: alertMem) { Alerts.shared.memThreshold = $0 }
                    thresholdRow("GPU 占用", value: $alertGPUUtil, range: 50...99, unit: "%")
                        .onChange(of: alertGPUUtil) { Alerts.shared.gpuUtilThreshold = $0 }
                    thresholdRow("GPU 温度", value: $alertGPUTemp, range: 60...110, unit: "°C")
                        .onChange(of: alertGPUTemp) { Alerts.shared.gpuTempThreshold = $0 }
                    thresholdRow("GPU 功耗", value: $alertGPUPower, range: 5...40, unit: "W")
                        .onChange(of: alertGPUPower) { Alerts.shared.gpuPowerThreshold = $0 }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func thresholdRow(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text(name).font(.callout)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue))\(unit)").font(.callout.monospaced()).frame(width: 56, alignment: .trailing)
        }
    }

    // MARK: 工具

    private var toolsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("系统权限", subtitle: "仅「实时 CPU 频率」需要管理员权限；温度/风扇/功耗均已免授权")
                Toggle(isOn: adminBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("管理员模式（实时 CPU 频率）").font(.callout)
                        Text("通过 powermetrics 获取实时睿频；老 Intel 硬件无免授权实时频率通道").font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                Divider()

                sectionTitle("硬件监控驱动", subtitle: "安装后免密码读取实时频率与各域功率（一次性授权）")
                VStack(alignment: .leading, spacing: 8) {
                    switch kextStatus {
                    case .ready:
                        HStack(spacing: 8) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("驱动已加载（接口 v\(KextMetrics.expectedKextVersion)）").font(.callout)
                            Spacer()
                        }
                    case .outdated(let v):
                        HStack(spacing: 8) {
                            Circle().fill(Color.orange).frame(width: 8, height: 8)
                            Text(v > 0 ? "检测到旧版驱动（接口 v\(v)，需要 v\(KextMetrics.expectedKextVersion)），请更新"
                                       : "检测到旧版驱动（无版本信息），请更新").font(.callout)
                            Spacer()
                        }
                    case .notInstalled:
                        HStack(spacing: 8) {
                            Circle().fill(Color.gray).frame(width: 8, height: 8)
                            Text("驱动未安装").font(.callout)
                            Spacer()
                        }
                    }
                    Text("SuperStateKext 内核扩展：逐核实时频率（MSR）+ 整机/CPU 核心/核显/内存功率（RAPL）。仅读取、不写任何寄存器。")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("驱动已内置在本 App 中，无需单独下载或联网；分享本 App 给对方，对方点上面的安装按钮（一次密码）即可使用。")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        if kextStatus != .ready {
                            Button(kextStatusIsOutdated ? "更新驱动（需一次密码）" : "安装硬件监控驱动（需一次密码）") {
                                installing = true
                                KextMetrics.install { ok, err in
                                    refreshKextStatus()
                                    installing = false
                                    if ok {
                                        installMsg = kextStatus == .ready
                                            ? "安装完成，驱动已更新并加载。"
                                            : "安装完成但尚未生效，请完全退出 SuperState 后重新打开，再点一次更新。"
                                    } else {
                                        installMsg = err ?? "安装失败"
                                    }
                                }
                            }
                            .disabled(installing)
                        }
                        if kextStatus != .notInstalled {
                            Button("卸载驱动", role: .destructive) {
                                uninstalling = true
                                KextMetrics.uninstall { ok, err in
                                    refreshKextStatus()
                                    uninstalling = false
                                    installMsg = ok ? "驱动已卸载" : (err ?? "卸载失败")
                                }
                            }
                            .disabled(uninstalling)
                        }
                    }
                    if !installMsg.isEmpty {
                        Text(installMsg).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("提示：若安装时系统弹出英文的「System … blocked」允许提示，请到 系统设置 → 隐私与安全性 中点「允许」并重试安装（仅需一次）。")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Divider()

                sectionTitle("启动与窗口", subtitle: nil)
                Toggle("开机自动启动", isOn: $launchOn).onChange(of: launchOn) { QuickActions.launchAtLogin = $0 }

                HStack(spacing: 10) {
                    Button("清空废纸篓") { QuickActions.emptyTrash { _, _ in } }
                    Button("打开网速悬浮窗") { FloatingWindowController.shared.toggle() }
                    Spacer()
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func sectionTitle(_ t: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.headline)
            if let s = subtitle { Text(s).font(.caption).foregroundStyle(.tertiary) }
        }
    }

    /// 管理员模式开关绑定：同状态面板逻辑，仅用户真实切换时才执行，
    /// 避免 syncAll() 同步状态时重复弹出密码框（ThermalMetrics 回调已在主队列，可直接更新 @State）
    private var adminBinding: Binding<Bool> {
        Binding(
            get: { adminOn },
            set: { newValue in
                guard newValue != ThermalMetrics.shared.adminEnabled else {
                    adminOn = ThermalMetrics.shared.adminEnabled
                    return
                }
                adminOn = newValue
                if newValue {
                    ThermalMetrics.shared.enable { ok, _ in
                        if !ok { adminOn = false }
                    }
                } else {
                    ThermalMetrics.shared.disable { _, _ in }
                }
            }
        )
    }
}

// MARK: - macOS 26 液态玻璃 Tab 栏

/// 系统 Liquid Glass 风格分段 Tab 栏：
/// macOS 26+ 使用 glassEffect + GlassEffectContainer，旧系统降级为 ultraThinMaterial 胶囊
struct GlassTabBar: View {
    @Binding var selection: Int
    let tabs: [(id: Int, title: String, icon: String)]

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 2) {
                    ForEach(tabs, id: \.id) { tab in
                        tabButton(tab)
                    }
                }
                .padding(3)
                .glassEffect(.regular, in: .capsule)
            }
        } else {
            HStack(spacing: 2) {
                ForEach(tabs, id: \.id) { tab in
                    tabButton(tab)
                }
            }
            .padding(3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
    }

    private func tabButton(_ tab: (id: Int, title: String, icon: String)) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { selection = tab.id }
        } label: {
            Label(tab.title, systemImage: tab.icon)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(selection == tab.id ? Color.primary : Color.secondary)
                .background {
                    // 选中项：浅色药丸（非玻璃，避免玻璃叠玻璃）
                    if selection == tab.id {
                        Capsule().fill(Color.primary.opacity(0.12))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

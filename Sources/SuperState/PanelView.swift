import SwiftUI

/// 主状态面板：概览 + 核显/独显双模块 + 进程 + 设置
struct PanelView: View {
    @ObservedObject var monitor = Monitor.shared
    @State private var showTrashDone = false
    @State private var cpuExpanded = false
    @State private var adminOn = ThermalMetrics.shared.adminEnabled
    @State private var launchOn = QuickActions.launchAtLogin
    @State private var floatOn = FloatingWindowController.shared.isVisible
    @State private var alertEnabled = Alerts.shared.enabled
    @State private var alertCPU = Alerts.shared.cpuThreshold
    @State private var alertMem = Alerts.shared.memThreshold
    @State private var alertGPUUtil = Alerts.shared.gpuUtilThreshold
    @State private var alertGPUTemp = Alerts.shared.gpuTempThreshold
    @State private var adminMessage: String?

    private var history: HistoryStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                // 概览
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    // CPU：点击卡片展开 / 收起 4核8线程
                    VStack(spacing: 8) {
                        MetricCard(title: cpuExpanded ? "CPU 占用（点击收起）" : "CPU 占用（点击展开）",
                                   value: String(format: "%.0f%%", monitor.snapshot.cpuUsage),
                                   detail: cpuDetail,
                                   data: history.cpu,
                                   color: .blue)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) { cpuExpanded.toggle() }
                            }
                        if cpuExpanded {
                            CPUCoresPanel(threads: monitor.snapshot.cpuCoreUsages, freqText: panelFreqText, powerText: panelPowerText)
                        }
                    }
                    MetricCard(title: "内存",
                               // 主数值 = 内存压力（活动监视器口径），按压力等级变色
                               value: String(format: "%.0f%%", monitor.snapshot.memPressurePercent),
                               detail: memDetail,
                               data: history.mem,
                               color: .orange,
                               barValue: monitor.snapshot.memPressurePercent,
                               barColor: pressureColor(monitor.snapshot.memPressurePercent))
                    // GPU 小卡片：独显 / 核显分开显示
                    if let dgpu = monitor.snapshot.gpus.first(where: { !$0.isIntegrated }),
                       let idx = monitor.snapshot.gpus.firstIndex(where: { $0.name == dgpu.name }) {
                        MetricCard(title: "独显",
                                   value: String(format: "%.0f%%", dgpu.utilization),
                                   detail: gpuCardDetail(dgpu),
                                   data: idx < history.gpuUtil.count ? history.gpuUtil[idx] : [],
                                   color: .purple)
                    }
                    if let igpu = monitor.snapshot.gpus.first(where: { $0.isIntegrated }),
                       let idx = monitor.snapshot.gpus.firstIndex(where: { $0.name == igpu.name }) {
                        MetricCard(title: "核显",
                                   value: String(format: "%.0f%%", igpu.utilization),
                                   detail: gpuCardDetail(igpu),
                                   data: idx < history.gpuUtil.count ? history.gpuUtil[idx] : [],
                                   color: .teal)
                    }
                    MetricCard(title: "磁盘",
                               value: String(format: "%.0f%%", monitor.snapshot.diskUsedPercent),
                               detail: diskDetail,
                               data: [],
                               color: .green)
                    MetricCard(title: "网络",
                               value: String(format: "↓ %@", Format.rate(monitor.snapshot.netDownBytesPerSec)),
                               detail: netDetail,
                               data: history.netDown.map { $0 / 1_048_576 },
                               color: .teal,
                               maxValue: max(1, (history.netDown.max() ?? 1_048_576) / 1_048_576))
                }

                // CPU 大卡片：总体利用率 + 逻辑处理器切换 + 详细信息（面板场景默认折叠）
                CPUDetailCard(detailCollapsedByDefault: true)

                // 内存大卡片：速度（MT/s）/ 插槽或焊接 / 压力 / Swap
                MemoryDetailCard()

                // GPU 模块：核显 / 独显拆分（始终显示）
                if monitor.snapshot.gpus.isEmpty {
                    Text("未检测到可用的 GPU 数据")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(monitor.snapshot.gpus.enumerated()), id: \.element.name) { idx, gpu in
                        GPUCard(gpu: gpu,
                                history: idx < history.gpuUtil.count ? history.gpuUtil[idx] : [],
                                index: idx)
                    }
                    Text("温度 / 独显频率 / 独显功耗（导轨）均免授权；核显断电时其频率与功耗无数据")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                // 进程（始终显示）
                processSection

                // 告警设置
                alertSection

                // 快捷工具
                toolsSection
            }
            .padding(14)
        }
        .frame(width: 460)
        .onAppear { syncSettings() }
        .onReceive(NotificationCenter.default.publisher(for: .adminModeChanged)) { _ in
            adminOn = ThermalMetrics.shared.adminEnabled
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SuperState").font(.title3.bold())
                Text("已运行 \(Format.uptime(monitor.snapshot.uptimeSeconds))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if ThermalMetrics.shared.adminEnabled {
                Label("管理员模式", systemImage: "checkmark.shield.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            Button {
                MainWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("打开主界面（设置）")
            Text("电池 \(monitor.snapshot.batteryTempC.map { String(format: "%.0f°C", $0) } ?? "–")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var cpuDetail: String {
        var parts: [String] = []
        if let f = monitor.snapshot.cpuFreqMhz { parts.append(String(format: "%.2fGHz", f / 1000)) }
        parts.append("热级 \(monitor.snapshot.cpuThermalLevel)")
        if let t = monitor.snapshot.cpuTempC { parts.append(String(format: "%.0f°C", t)) }
        if let p = monitor.snapshot.packagePowerWatts { parts.append("整机 \(Format.power(p))") }
        else if let p = monitor.snapshot.cpuPowerWatts { parts.append(Format.power(p)) }
        return parts.joined(separator: " · ")
    }

    /// CPU 展开面板的频率行：管理员模式或已装驱动显示"当前（实时）/ 基础 / 睿频"；否则只显示基础 / 睿频
    private var panelFreqText: String {
        let cpu = CPUInfo.shared
        var parts: [String] = []
        if (ThermalMetrics.shared.adminEnabled || KextMetrics.shared.isAvailable),
           let f = monitor.snapshot.cpuFreqMhz {
            parts.append("当前 \(Format.gpuFreq(f))")
        }
        if cpu.baseFreqMHz > 0 { parts.append("基础 \(Format.gpuFreq(cpu.baseFreqMHz))") }
        if cpu.maxFreqMHz > 0 { parts.append("睿频 \(Format.gpuFreq(cpu.maxFreqMHz))") }
        return parts.isEmpty ? "频率–" : parts.joined(separator: " · ")
    }

    /// GPU 小卡片明细：温度 · 频率 · 功耗 / 功耗上限
    private func gpuCardDetail(_ g: GPUSnapshot) -> String {
        var parts: [String] = []
        if let t = g.temperatureC { parts.append(String(format: "%.0f°C", t)) }
        parts.append("频率 \(g.freqText)")
        if let p = g.powerWatts { parts.append(Format.power(p)) }
        else if let limit = g.powerLimitWatts { parts.append("上限 \(Format.power(limit))") }
        return parts.joined(separator: " · ")
    }

    private var memDetail: String {
        "占用 \(String(format: "%.0f%%", monitor.snapshot.memUsedPercent)) · 活跃 \(Format.bytes(monitor.snapshot.memActiveBytes)) · Swap \(Format.bytes(monitor.snapshot.swapUsedBytes))"
    }

    /// 核线程面板的功耗摘要
    private var panelPowerText: String {
        var parts: [String] = []
        if let p = monitor.snapshot.cpuPowerWatts { parts.append("核心 \(Format.power(p))") }
        if let p = monitor.snapshot.packagePowerWatts { parts.append("整机 \(Format.power(p))") }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    private var diskDetail: String {
        if Settings.panelShowDiskIO {
            return "读 \(Format.rate(monitor.snapshot.diskReadBytesPerSec)) · 写 \(Format.rate(monitor.snapshot.diskWriteBytesPerSec))"
        }
        return "\(Format.bytes(monitor.snapshot.diskFreeBytes)) 可用"
    }

    private var netDetail: String {
        "↑ \(Format.rate(monitor.snapshot.netUpBytesPerSec)) · 累计 ↑\(Format.bytes(monitor.snapshot.netUpTotalBytes)) ↓\(Format.bytes(monitor.snapshot.netDownTotalBytes))"
    }

    // MARK: - 进程

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("占用最高的进程").font(.headline)
            ForEach(monitor.snapshot.topProcesses, id: \.pid) { p in
                HStack(spacing: 8) {
                    Text(p.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.0f%%", p.cpu)).font(.system(size: 12, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                    Text(Format.bytes(p.memBytes)).font(.system(size: 12, design: .monospaced))
                        .frame(width: 64, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
            }
            if monitor.snapshot.topProcesses.isEmpty {
                Text("暂无数据").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 告警

    private var alertSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $alertEnabled) {
                Text("智能告警").font(.headline)
            }
            .onChange(of: alertEnabled) { Alerts.shared.enabled = $0 }

            if alertEnabled {
                HStack {
                    Text("CPU 占用").font(.caption)
                    Slider(value: $alertCPU, in: 50...99, step: 1)
                    Text("\(Int(alertCPU))%").font(.caption.monospaced())
                }
                HStack {
                    Text("内存压力").font(.caption)
                    Slider(value: $alertMem, in: 50...99, step: 1)
                    Text("\(Int(alertMem))%").font(.caption.monospaced())
                }
                HStack {
                    Text("GPU 占用").font(.caption)
                    Slider(value: $alertGPUUtil, in: 50...99, step: 1)
                    Text("\(Int(alertGPUUtil))%").font(.caption.monospaced())
                }
                HStack {
                    Text("GPU 温度").font(.caption)
                    Slider(value: $alertGPUTemp, in: 60...110, step: 1)
                    Text("\(Int(alertGPUTemp))°C").font(.caption.monospaced())
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: alertCPU) { Alerts.shared.cpuThreshold = $0 }
        .onChange(of: alertMem) { Alerts.shared.memThreshold = $0 }
        .onChange(of: alertGPUUtil) { Alerts.shared.gpuUtilThreshold = $0 }
        .onChange(of: alertGPUTemp) { Alerts.shared.gpuTempThreshold = $0 }
    }

    // MARK: - 快捷工具

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷工具").font(.headline)

            Toggle(isOn: adminBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("管理员模式（实时 CPU 频率）")
                    Text("温度、风扇、功耗均已免授权；仅实时频率需输入一次密码")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if let msg = adminMessage {
                Text(msg).font(.caption2).foregroundStyle(.red)
            }

            Toggle(isOn: $launchOn) {
                Text("开机自动启动")
            }
            .onChange(of: launchOn) { QuickActions.launchAtLogin = $0 }

            Toggle(isOn: $floatOn) {
                Text("网速悬浮窗")
            }
            .onChange(of: floatOn) { _ in
                FloatingWindowController.shared.toggle()
                floatOn = FloatingWindowController.shared.isVisible
            }

            HStack(spacing: 10) {
                Button("清空废纸篓") {
                    QuickActions.emptyTrash { ok, err in
                        showTrashDone = true
                    }
                }
                .alert("清空废纸篓", isPresented: $showTrashDone) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text("已执行清空操作")
                }

                Spacer()

                Menu {
                    ForEach(QuickActions.installedApplications(), id: \.path) { url in
                        Button(url.lastPathComponent.replacingOccurrences(of: ".app", with: "")) {
                            QuickActions.openApplication(url)
                        }
                    }
                } label: {
                    Label("快速启动 App", systemImage: "app.badge")
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func syncSettings() {
        alertEnabled = Alerts.shared.enabled
        alertCPU = Alerts.shared.cpuThreshold
        alertMem = Alerts.shared.memThreshold
        alertGPUUtil = Alerts.shared.gpuUtilThreshold
        alertGPUTemp = Alerts.shared.gpuTempThreshold
        adminOn = ThermalMetrics.shared.adminEnabled
        launchOn = QuickActions.launchAtLogin
        floatOn = FloatingWindowController.shared.isVisible
    }

    /// 管理员模式开关绑定。
    /// 关键：只有「用户真实切换」（新值与 ThermalMetrics 实际状态不一致）时才执行 enable/disable，
    /// 避免 onAppear / syncSettings 同步开关状态时误触发 enable、再次弹出管理员密码框。
    private var adminBinding: Binding<Bool> {
        Binding(
            get: { adminOn },
            set: { newValue in
                guard newValue != ThermalMetrics.shared.adminEnabled else {
                    // 仅状态同步，不触发任何副作用
                    adminOn = ThermalMetrics.shared.adminEnabled
                    return
                }
                adminOn = newValue
                adminMessage = nil
                if newValue {
                    ThermalMetrics.shared.enable { ok, err in
                        if !ok {
                            adminOn = false
                            adminMessage = err ?? "开启失败"
                        }
                    }
                } else {
                    ThermalMetrics.shared.disable { _, _ in }
                }
            }
        )
    }
}

// MARK: - GPU 卡片（核显 / 独显拆分显示）

struct GPUCard: View {
    let gpu: GPUSnapshot
    let history: [Double]
    let index: Int

    private var accent: Color { gpu.isIntegrated ? .blue : .purple }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: gpu.isIntegrated ? "cpu" : "bolt.fill")
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(gpu.displayName).font(.headline)
                    Text(gpu.isIntegrated ? "集成显卡" : "独立显卡")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(String(format: "%.0f%%", gpu.utilization))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
            }

            Sparkline(data: history, color: accent)

            HStack(spacing: 12) {
                metricPill(icon: "thermometer", text: tempText)
                metricPill(icon: "bolt", text: powerText)
                metricPill(icon: "waveform", text: freqText)
                Spacer()
            }
            .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(gpu.isIntegrated ? "显存（动态共享）" : "显存占用")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(gpu.vramTotalBytes > 0
                         ? String(format: "%.0f / %.0f MB", gpu.vramUsedMB, gpu.vramTotalMB)
                         : Format.bytes(gpu.vramUsedBytes))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if gpu.vramTotalBytes > 0 {
                    Bar(value: gpu.vramPercent, color: accent)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var tempText: String {
        if let t = gpu.temperatureC { return String(format: "%.0f°C", t) }
        return "温度 –"
    }

    private var powerText: String {
        if let p = gpu.powerWatts { return Format.power(p) }
        // 老硬件无实时功耗：显示 SMC 功率上限（免授权），明确标注是上限
        if let limit = gpu.powerLimitWatts { return "上限 \(Format.power(limit))" }
        return "功耗 –"
    }

    private var freqText: String {
        if let f = gpu.freqMhz { return String(format: "%.0f MHz", f) }
        return "频率 –"
    }

    private func metricPill(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(text)
        }
    }
}

extension Notification.Name {
    static let adminModeChanged = Notification.Name("SuperState.adminModeChanged")
}

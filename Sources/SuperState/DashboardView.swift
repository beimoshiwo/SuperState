import SwiftUI

// MARK: - 仪表盘（主程序内的实时监控数据卡片）

struct DashboardView: View {
    @ObservedObject var monitor = Monitor.shared
    @State private var cpuExpanded = false
    /// 内存小卡：false=占用率模式，true=压力模式（点击切换）
    @State private var memCardPressure = false
    private var history: HistoryStore { .shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                systemInfoCard

                // 核心监控卡片
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    // CPU：点击卡片展开 / 收起 4核8线程
                    VStack(spacing: 8) {
                        MetricCard(title: cpuExpanded ? "CPU 占用（点击收起）" : "CPU 占用（点击展开 4核8线程）",
                                   value: String(format: "%.0f%%", s.cpuUsage),
                                   detail: cpuDetail,
                                   data: history.cpu,
                                   color: .blue)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) { cpuExpanded.toggle() }
                            }
                        if cpuExpanded {
                            CPUCoresPanel(threads: s.cpuCoreUsages, freqText: freqText, powerText: powerText)
                        }
                    }

                    if let igpu = s.gpus.first(where: { $0.isIntegrated }),
                       let idx = s.gpus.firstIndex(where: { $0.isIntegrated }) {
                        MetricCard(title: "核显占用",
                                   value: String(format: "%.0f%%", igpu.utilization),
                                   detail: gpuDetail(igpu),
                                   data: idx < history.gpuUtil.count ? history.gpuUtil[idx] : [],
                                   color: .teal)
                    }

                    if let dgpu = s.gpus.first(where: { !$0.isIntegrated }),
                       let idx = s.gpus.firstIndex(where: { !$0.isIntegrated }) {
                        MetricCard(title: "独显占用",
                                   value: String(format: "%.0f%%", dgpu.utilization),
                                   detail: gpuDetail(dgpu),
                                   data: idx < history.gpuUtil.count ? history.gpuUtil[idx] : [],
                                   color: .purple)
                    }

                    // 内存小卡：点击在占用率与压力之间切换（压力模式按等级变色）
                    MetricCard(title: memCardPressure ? "内存压力" : "内存占用",
                               value: String(format: "%.0f%%", memCardPressure ? s.memPressurePercent : s.memUsedPercent),
                               detail: memCardPressure
                                   ? "占用 \(String(format: "%.0f%%", s.memUsedPercent)) · Swap \(Format.bytes(s.swapUsedBytes))"
                                   : "压力 \(String(format: "%.0f%%", s.memPressurePercent)) · Swap \(Format.bytes(s.swapUsedBytes))",
                               data: history.mem,
                               color: .orange,
                               barValue: memCardPressure ? s.memPressurePercent : s.memUsedPercent,
                               barColor: memCardPressure ? pressureColor(s.memPressurePercent) : .orange)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { memCardPressure.toggle() }
                        }

                    MetricCard(title: "磁盘占用",
                               value: String(format: "%.0f%%", s.diskUsedPercent),
                               detail: "读 \(Format.rate(s.diskReadBytesPerSec)) · 写 \(Format.rate(s.diskWriteBytesPerSec)) · \(Format.bytes(s.diskFreeBytes))可用",
                               data: [],
                               color: .green)

                    MetricCard(title: "网络（↓下行）",
                               value: Format.rate(s.netDownBytesPerSec),
                               detail: "↑ \(Format.rate(s.netUpBytesPerSec)) · 累计 ↓\(Format.bytes(s.netDownTotalBytes))",
                               data: history.netDown.map { $0 / 1_048_576 },
                               color: .cyan,
                               maxValue: max(1, (history.netDown.max() ?? 1_048_576) / 1_048_576))
                }

                // CPU / 内存大卡片（与状态面板共用）
                CPUDetailCard()
                MemoryDetailCard()

                // 风扇 + 电池
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    fanCard
                    batteryCard
                }

                // CPU 核心/模块温度
                if !s.cpuCoreTemps.isEmpty {
                    coreTempCard
                }

                // 双 GPU 详情
                ForEach(Array(s.gpus.enumerated()), id: \.element.name) { idx, gpu in
                    GPUCard(gpu: gpu,
                            history: idx < history.gpuUtil.count ? history.gpuUtil[idx] : [],
                            index: idx)
                }
            }
            .padding(14)
        }
    }

    private var s: SystemSnapshot { monitor.snapshot }

    // MARK: 系统信息

    private var systemInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow("系统版本", DashboardInfo.osVersion)
            if PlatformIdentity.isPatched {
                infoRow("原生机型", PlatformIdentity.nativeModel ?? "无法确定")
                infoRow("报告机型（SMBIOS）", PlatformIdentity.reportedModel)
                infoRow("运行环境", PlatformIdentity.environment.rawValue)
            } else {
                infoRow("型号标识", PlatformIdentity.reportedModel)
            }
            infoRow("CPU", DashboardInfo.cpu)
            infoRow("GPU", s.gpus.map { $0.name }.joined(separator: " + "))
            infoRow("内存", Format.bytes(s.memTotalBytes))
            infoRow("开机时长", Format.uptime(s.uptimeSeconds))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption).multilineTextAlignment(.trailing)
        }
    }

    // MARK: 风扇 / 电池

    private var fanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("风扇").font(.caption).foregroundStyle(.secondary)
            if s.fans.isEmpty {
                Text("未检测到风扇").font(.caption2).foregroundStyle(.tertiary)
            } else {
                ForEach(s.fans, id: \.id) { fan in
                    HStack {
                        Text(fan.name).font(.system(size: 12))
                        Spacer()
                        Text(String(format: "%.0f rpm", fan.rpm))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("电池").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("电池温度").font(.system(size: 12))
                Spacer()
                Text(s.batteryTempC.map { String(format: "%.1f°C", $0) } ?? "–")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: CPU 核心温度

    private var coreTempCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CPU 核心 / 模块温度").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(s.cpuCoreTemps.enumerated()), id: \.offset) { _, c in
                HStack(spacing: 8) {
                    Text(c.label).font(.system(size: 11, design: .monospaced)).frame(width: 44, alignment: .leading)
                    Bar(value: min(c.tempC, 100), color: c.tempC >= 80 ? .red : (c.tempC >= 60 ? .orange : .blue))
                    Text(String(format: "%.1f°C", c.tempC))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced)).frame(width: 52, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: CPU 4核8线程展开面板（与状态面板共用 CPUCoresPanel）

    private var freqText: String {
        guard let f = s.cpuFreqMhz else { return "频率–" }
        return String(format: "%.2f GHz", f / 1000)
    }

    /// 核线程面板的功耗摘要（核心 / 整机）
    private var powerText: String {
        var parts: [String] = []
        if let p = s.cpuPowerWatts { parts.append("核心 \(Format.power(p))") }
        if let p = s.packagePowerWatts { parts.append("整机 \(Format.power(p))") }
        return parts.isEmpty ? "" : parts.joined(separator: " · ")
    }

    // MARK: 明细

    private var cpuDetail: String {
        var parts: [String] = []
        if let f = s.cpuFreqMhz { parts.append(String(format: "%.2fGHz", f / 1000)) }
        if let t = s.cpuTempC { parts.append(String(format: "%.0f°C", t)) }
        if let p = s.packagePowerWatts { parts.append("整机\(Format.power(p))") }
        else if let p = s.cpuPowerWatts { parts.append(Format.power(p)) }
        parts.append("热级\(s.cpuThermalLevel)")
        return parts.joined(separator: " · ")
    }

    private func gpuDetail(_ g: GPUSnapshot) -> String {
        var parts: [String] = []
        if let t = g.temperatureC { parts.append(String(format: "%.0f°C", t)) }
        if let f = g.freqMhz { parts.append(String(format: "%.0fMHz", f)) }
        if g.vramTotalBytes > 0 {
            parts.append(String(format: "显存%.0f/%.0fMB", g.vramUsedMB, g.vramTotalMB))
        }
        if let p = g.powerWatts { parts.append(Format.power(p)) }
        else if let limit = g.powerLimitWatts { parts.append("上限\(Format.power(limit))") }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}

// MARK: - 系统静态信息

enum DashboardInfo {
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
    static var model: String { sysctlString("hw.model") }
    static var cpu: String { sysctlString("machdep.cpu.brand_string") }

    static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "–" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }
}

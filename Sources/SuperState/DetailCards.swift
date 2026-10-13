import SwiftUI

// MARK: - CPU 逻辑处理器（线程）实时占用面板
// 仪表盘与状态面板共用：上半区 T0~Tn 逐条实时占用

struct CPUCoresPanel: View {
    var threads: [Double]
    var freqText: String
    /// 功耗摘要（如 "核心 2.1W · 整机 4.3W"），可为空
    var powerText: String = ""

    private var physical: Int { max(1, threads.count / 2) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(physical) 核 \(threads.count) 线程实时占用")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if !powerText.isEmpty {
                    Text(powerText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(freqText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ForEach(0..<physical, id: \.self) { core in
                HStack(spacing: 6) {
                    Text("核\(core)").font(.system(size: 9))
                        .foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                    threadMini(core, threads)
                    threadMini(core + physical, threads)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// 物理核分组视图的小占用条（带 T 线程编号）
    private func threadMini(_ i: Int, _ threads: [Double]) -> some View {
        let u = i < threads.count ? threads[i] : 0
        return HStack(spacing: 3) {
            Text("T\(i)").font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary).frame(width: 20)
            Bar(value: u, color: u > 80 ? .orange : .blue)
            Text(String(format: "%.0f%%", u))
                .font(.system(size: 8, design: .monospaced))
                .frame(width: 30, alignment: .trailing)
        }
    }
}

// MARK: - CPU 大卡片（状态面板 / 仪表盘共用）

/// 详细 CPU 卡片：总体利用率 + 逻辑处理器实时占用 + 静态信息 + 免授权功率
struct CPUDetailCard: View {
    @ObservedObject var monitor = Monitor.shared

    /// 状态面板场景：详细信息默认折叠，点击展开（仪表盘不传此参数，保持展开）
    var detailCollapsedByDefault = false
    @State private var detailExpanded = false

    /// 显式初始化器（结构体含私有存储属性时成员初始化器不可带参）
    init(monitor: Monitor = .shared, detailCollapsedByDefault: Bool = false) {
        self.monitor = monitor
        self.detailCollapsedByDefault = detailCollapsedByDefault
    }

    private var history: HistoryStore { .shared }
    private var cpu = CPUInfo.shared
    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部：型号 + 总体利用率
            HStack(spacing: 6) {
                Image(systemName: "cpu").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cpu.brand).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text("\(cpu.physicalCores) 核 \(cpu.logicalCpus) 线程 · \(cpu.packageType)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(String(format: "%.0f%%", s.cpuUsage))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue)
            }

            Sparkline(data: history.cpu, color: .blue)

            // 逻辑处理器（线程）切换展示
            CPUCoresPanel(threads: s.cpuCoreUsages, freqText: freqText)

            Divider()

            if detailCollapsedByDefault && !detailExpanded {
                // 折叠态：一行入口，点击展开详细信息
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Text("详细信息").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { detailExpanded = true }
                }
            } else {
                // 详细信息
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 6) {
                    row("内核数", "\(cpu.physicalCores)")
                    row("逻辑处理器", "\(cpu.logicalCpus)")
                    row("CPU 封装", cpu.packageType)
                    row("虚拟化", cpu.virtualization ? "支持（VT-x）" : "不支持")
                    row("睿频加速", cpu.turboMHz.map { Format.gpuFreq($0) } ?? "–")
                    row("核显最大频率", cpu.igpuMaxMHz.map { Format.gpuFreq($0) } ?? "–")
                    row("进程数", s.processCount > 0 ? "\(s.processCount)" : "–")
                    row("线程数", s.threadCount > 0 ? "\(s.threadCount)" : "–")
                    row("句柄数", s.fileCount > 0 ? "\(s.fileCount)" : "–")
                    row("本次运行", Format.uptime(s.uptimeSeconds))
                    row("CPU 核心功率", s.cpuPowerWatts.map { Format.power($0) } ?? "–")
                    row("整机功率", s.packagePowerWatts.map { Format.power($0) } ?? "–")
                    if let d = s.dramPowerWatts { row("内存(DRAM)功率", Format.power(d)) }
                }
                // 缓存较长，单独一行
                HStack {
                    Text("缓存").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(cpu.cacheText).font(.caption.monospaced())
                }
                if detailCollapsedByDefault {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.tertiary)
                        Text("收起详细信息").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { detailExpanded = false }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 管理员模式或已装驱动显示"当前（实时）"；否则只显示基础 / 睿频（官方规格）
    private var freqText: String {
        var parts: [String] = []
        if (ThermalMetrics.shared.adminEnabled || KextMetrics.shared.isAvailable),
           let f = s.cpuFreqMhz {
            parts.append("当前 \(Format.gpuFreq(f))")
        }
        if cpu.baseFreqMHz > 0 { parts.append("基础 \(Format.gpuFreq(cpu.baseFreqMHz))") }
        if let t = cpu.turboMHz { parts.append("睿频 \(Format.gpuFreq(t))") }
        return parts.isEmpty ? "频率–" : parts.joined(separator: " · ")
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.monospaced()).lineLimit(1).truncationMode(.tail)
        }
    }
}

// MARK: - 内存大卡片（状态面板 / 仪表盘共用）

/// 详细内存卡片：占用/压力点击切换 + 速度（MT/s）+ 插槽或焊接
struct MemoryDetailCard: View {
    @ObservedObject var monitor = Monitor.shared
    @ObservedObject var probe = MemoryProbe.shared
    /// true=显示内存压力（活动监视器风格，按压力等级绿/橙/红），false=显示占用率
    @State private var showPressure = false

    /// 压力模式下颜色随压力等级变化；占用率模式固定橙色
    private var accentColor: Color {
        showPressure ? pressureColor(s.memPressurePercent) : .orange
    }

    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "memorychip").foregroundStyle(accentColor)
                // 点击标题在占用率与压力之间切换
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showPressure.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(showPressure ? "内存压力" : "内存").font(.headline)
                        Text("（点击切换）").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(String(format: "%.0f%%", showPressure ? s.memPressurePercent : s.memUsedPercent))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { showPressure.toggle() }
                    }
            }

            Bar(value: showPressure ? s.memPressurePercent : s.memUsedPercent,
                color: accentColor)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 6) {
                row("已用", "\(Format.bytes(s.memUsedBytes)) / \(Format.bytes(s.memTotalBytes))")
                row("内存占用率", String(format: "%.0f%%", s.memUsedPercent))
                row("内存压力", String(format: "%.0f%%", s.memPressurePercent))
                row("Swap", "\(Format.bytes(s.swapUsedBytes)) / \(Format.bytes(s.swapTotalBytes))")
                row("速度", speedText)
                row("类型", probe.info?.type ?? "–")
                row("封装", probe.info?.slotText ?? "–")
            }
            HStack {
                Text("活跃 / 联动 / 压缩").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Format.bytes(s.memActiveBytes)) · \(Format.bytes(s.memWiredBytes)) · \(Format.bytes(s.memCompressedBytes))")
                    .font(.caption.monospaced())
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// DDR 等效传输速率：system_profiler 的 "Speed: 1600 MHz" 即 1600 MT/s
    private var speedText: String {
        guard let mt = probe.info?.speedMTs, mt > 0 else { return "–" }
        return "\(mt) MT/s"
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.monospaced()).lineLimit(1).truncationMode(.tail)
        }
    }
}

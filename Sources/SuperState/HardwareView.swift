import SwiftUI

// MARK: - 硬件参数页（图吧工具箱风格：分区卡片 + 标签/数值两列）

struct HardwareView: View {
    @ObservedObject var monitor = Monitor.shared
    @ObservedObject var hw = HardwareInfo.shared
    @ObservedObject var mem = MemoryProbe.shared

    private var cpu = CPUInfo.shared
    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 系统
                HWSection(title: "系统", icon: "desktopcomputer") {
                    row("操作系统", HWSystemInfo.osVersion)
                    row("构建号", HWSystemInfo.osBuild)
                    row("内核版本", HWSystemInfo.kernelVersion)
                    row("机型标识", DashboardInfo.sysctlString("hw.model"))
                    row("主板 ID", HWSystemInfo.boardId)
                    row("序列号", HWSystemInfo.serial)
                    row("平台环境", PlatformIdentity.environment.rawValue)
                    if PlatformIdentity.isPatched {
                        row("出厂机型", PlatformIdentity.nativeModel ?? "无法确定")
                    }
                    if let boot = HWSystemInfo.bootDate {
                        row("启动时间", bootFormatter.string(from: boot))
                    }
                }

                // 处理器
                HWSection(title: "处理器", icon: "cpu") {
                    row("型号", cpu.brand)
                    if let model = cpu.modelNumber {
                        row("处理器编号", model)
                    }
                    if let spec = cpu.spec {
                        row("架构代号", spec.codename ?? "–")
                        row("制程工艺", spec.process ?? "–")
                        if let tdp = spec.tdpW { row("TDP", String(format: "%.0f W", tdp)) }
                        if let tj = spec.maxTempC { row("Tjunction", String(format: "%.0f °C", tj)) }
                        if let igpu = spec.igpuName {
                            row("集成显卡", igpu)
                            if let base = spec.igpuBaseMHz, let max = spec.igpuMaxMHz {
                                row("核显频率", "\(Format.gpuFreq(base)) ~ \(Format.gpuFreq(max))")
                            }
                        }
                    }
                    row("基础频率", Format.gpuFreq(cpu.baseFreqMHz))
                    row("最大睿频", cpu.turboMHz.map { Format.gpuFreq($0) } ?? "–")
                    row("核心 / 线程", "\(cpu.physicalCores) / \(cpu.logicalCpus)")
                    row("缓存", cpu.cacheText)
                    row("指令集", cpu.instructionSets)
                    row("虚拟化", cpu.virtualization ? "支持（VT-x）" : "不支持")
                    row("封装 / 插槽", cpu.packageType)
                    if let spec = cpu.spec, let socket = spec.socket {
                        row("插座型号", socket)
                    }
                }

                // 内存
                HWSection(title: "内存", icon: "memorychip") {
                    row("物理内存", Format.bytes(s.memTotalBytes))
                    if let info = mem.info {
                        row("类型", info.type ?? "–")
                        if let mt = info.speedMTs, mt > 0 { row("等效速率", "\(mt) MT/s") }
                        row("插槽 / 封装", info.slotText)
                    }
                }

                // 图形（实时）
                HWSection(title: "图形（实时）", icon: "display") {
                    if s.gpus.isEmpty {
                        Text("未检测到 GPU").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(s.gpus.enumerated()), id: \.element.name) { idx, g in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(g.displayName).font(.callout.weight(.medium))
                                    Spacer()
                                    Text(String(format: "%.0f%%", g.utilization))
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                        .foregroundStyle(g.isIntegrated ? .teal : .purple)
                                }
                                HStack(spacing: 10) {
                                    pill("温度", g.temperatureC.map { String(format: "%.0f°C", $0) } ?? "–")
                                    pill("频率", g.freqText)
                                    if let p = g.powerWatts { pill("功耗", Format.power(p)) }
                                    else if let l = g.powerLimitWatts { pill("功耗上限", Format.power(l)) }
                                    pill("显存", g.vramTotalBytes > 0
                                         ? String(format: "%.0f/%.0fMB", g.vramUsedMB, g.vramTotalMB)
                                         : Format.bytes(g.vramUsedBytes))
                                    if idx < s.gpus.count - 1 { Spacer() }
                                }
                                .font(.caption2)
                            }
                            if idx < s.gpus.count - 1 { Divider().padding(.vertical, 4) }
                        }
                    }
                }

                // 显示
                if !hw.displays.isEmpty {
                    HWSection(title: "显示", icon: "display.2") {
                        ForEach(Array(hw.displays.enumerated()), id: \.offset) { _, d in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(d.type ?? "显示器").font(.callout.weight(.medium))
                                    Spacer()
                                    if d.isMain { Text("主屏").font(.caption2).foregroundStyle(.blue) }
                                }
                                HStack(spacing: 10) {
                                    if let chip = d.chipset { pill("芯片", chip) }
                                    if let res = d.resolution { pill("分辨率", res) }
                                }
                                .font(.caption2)
                            }
                        }
                    }
                }

                // 存储
                if !hw.storages.isEmpty {
                    HWSection(title: "存储", icon: "internaldrive") {
                        ForEach(Array(hw.storages.enumerated()), id: \.offset) { _, st in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(st.deviceName ?? "存储卷").font(.callout.weight(.medium))
                                    Spacer()
                                    Text(Format.bytes(st.capacity)).font(.caption.monospaced())
                                }
                                HStack(spacing: 10) {
                                    pill("可用", Format.bytes(st.available))
                                    if let fs = st.fileSystem { pill("文件系统", fs) }
                                    if let med = st.mediumType { pill("介质", med) }
                                    if let proto = st.busProtocol { pill("协议", proto) }
                                    if let mount = st.mount { pill("挂载", mount) }
                                }
                                .font(.caption2)
                            }
                        }
                    }
                }

                // 网络
                if !hw.networks.isEmpty {
                    HWSection(title: "网络", icon: "network") {
                        ForEach(Array(hw.networks.enumerated()), id: \.offset) { _, n in
                            HStack {
                                Text("\(n.type ?? "接口")（\(n.bsd ?? "–")）").font(.callout.weight(.medium))
                                Spacer()
                                Text(n.ipv4.joined(separator: "、")).font(.caption.monospaced())
                            }
                        }
                    }
                }

                // 电池
                if let b = hw.battery {
                    HWSection(title: "电池", icon: "battery.100") {
                        row("循环次数", "\(b.cycleCount)")
                        if let health = b.healthPercent {
                            row("健康度", String(format: "%.1f%%", health))
                        }
                        row("当前最大容量", "\(b.maxCapacity) mAh")
                        row("设计容量", "\(b.designCapacity) mAh")
                        row("当前电量", "\(b.currentCapacity) mAh")
                        row("温度", String(format: "%.1f °C", b.temperatureC))
                        row("电压", String(format: "%.2f V", Double(b.voltageMV) / 1000))
                        row("状态", b.isCharging ? "充电中" : (b.fullyCharged ? "已充满" : "使用电池"))
                        row("外接电源", b.externalConnected ? "已连接" : "未连接")
                        if let m = b.manufacturer { row("制造商", m) }
                    }
                }

                if !hw.loaded {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("硬件信息采集中…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { hw.load() }
    }

    private var bootFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }

    private func pill(_ k: String, _ v: String) -> some View {
        HStack(spacing: 3) {
            Text(k).foregroundStyle(.secondary)
            Text(v)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.monospaced()).lineLimit(1).truncationMode(.tail)
        }
    }
}

/// 硬件分区卡片
struct HWSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

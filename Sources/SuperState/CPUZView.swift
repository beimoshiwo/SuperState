import SwiftUI

// MARK: - CPU-Z 风格硬件信息页（处理器 / 主板 / 内存 / SPD / 显卡）
// 所有字段均免授权；macOS 不暴露的项（如 SPD 详细时序）如实标注，不编造数据。

struct CPUZView: View {
    @ObservedObject var monitor = Monitor.shared
    @ObservedObject var hw = HardwareInfo.shared
    @ObservedObject var mem = MemoryProbe.shared

    private var cpu = CPUInfo.shared
    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                processorSection
                motherboardSection
                memorySection
                spdSection
                graphicsSection

                Text("以上信息全部免授权采集；标注「–」表示 macOS 未提供该数据通道，不做猜测填充。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { hw.load(); mem.load() }
    }

    // MARK: 处理器

    private var processorSection: some View {
        HWSection(title: "处理器", icon: "cpu") {
            row("型号", cpu.brand)
            row("厂商", cpuVendor)
            if let model = cpu.modelNumber { row("处理器编号", model) }
            if let spec = cpu.spec {
                if let codename = spec.codename { row("架构代号", codename) }
                if let process = spec.process { row("制程工艺", process) }
                if let tdp = spec.tdpW { row("TDP", String(format: "%.0f W", tdp)) }
                if let tj = spec.maxTempC { row("Tjunction", String(format: "%.0f °C", tj)) }
            }
            row("基础频率", Format.gpuFreq(cpu.baseFreqMHz))
            row("最大睿频", cpu.turboMHz.map { Format.gpuFreq($0) } ?? "–")
            row("核心 / 线程", "\(cpu.physicalCores) / \(cpu.logicalCpus)")
            row("路数", cpu.packages == 1 ? "单路" : "\(cpu.packages) 路")
            row("缓存", cpu.cacheText)
            row("指令集", cpu.instructionSets)
            row("虚拟化", cpu.virtualization ? "支持（VT-x）" : "不支持")
            row("封装 / 插槽", cpu.packageType)
            if let spec = cpu.spec, let igpu = spec.igpuName {
                if let base = spec.igpuBaseMHz, let max = spec.igpuMaxMHz {
                    row("集成显卡", "\(igpu)（\(Format.gpuFreq(base)) ~ \(Format.gpuFreq(max))）")
                } else {
                    row("集成显卡", igpu)
                }
            }
        }
    }

    private var cpuVendor: String {
        if cpu.brand.contains("Intel") { return "Intel" }
        if cpu.brand.contains("AMD") { return "AMD" }
        if cpu.brand.contains("Apple") { return "Apple" }
        return "–"
    }

    // MARK: 主板

    private var motherboardSection: some View {
        HWSection(title: "主板", icon: "server.rack") {
            row("机型标识", DashboardInfo.model)
            if let name = hw.sys?.modelName { row("机型名称", name) }
            row("主板 ID", HWSystemInfo.boardId)
            if let fw = hw.sys?.firmwareVersion { row("系统固件版本", fw) }
            if let smc = hw.sys?.smcVersion { row("SMC 版本", smc) }
            row("序列号", HWSystemInfo.serial)
            if let uuid = hw.sys?.hardwareUUID { row("硬件 UUID", uuid) }
            row("平台环境", PlatformIdentity.environment.rawValue)
            if PlatformIdentity.isPatched, let native = PlatformIdentity.nativeModel {
                row("出厂机型", native)
                Text("当前 SMBIOS 已被 OCLP/OpenCore 修补为 \(DashboardInfo.model)，上表固件/序列号等以修补后为准。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            row("操作系统", "\(HWSystemInfo.osVersion)（\(HWSystemInfo.osBuild)）")
        }
    }

    // MARK: 内存

    private var memorySection: some View {
        HWSection(title: "内存", icon: "memorychip") {
            row("总容量", Format.bytes(s.memTotalBytes))
            if let info = mem.info {
                if let type = info.type { row("类型", type) }
                if let mt = info.speedMTs, mt > 0 { row("等效速率", "\(mt) MT/s") }
                row("插槽 / 封装", info.slotText)
                if let ecc = info.eccEnabled { row("ECC", ecc ? "启用" : "禁用") }
            }
            row("已用", "\(Format.bytes(s.memUsedBytes))（\(String(format: "%.0f%%", s.memUsedPercent))）")
            row("可用", Format.bytes(s.memTotalBytes &- s.memUsedBytes))
            row("内存压力", "\(String(format: "%.0f%%", s.memPressurePercent))")
            row("交换分区", "\(Format.bytes(s.swapUsedBytes)) / \(Format.bytes(s.swapTotalBytes))")
        }
    }

    // MARK: SPD（每槽位静态信息）

    private var spdSection: some View {
        HWSection(title: "SPD（每槽位内存信息）", icon: "list.bullet") {
            let dimms = mem.info?.dimms ?? []
            if dimms.isEmpty {
                Text(mem.info == nil ? "采集中…" : "未检测到内存槽位信息")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(dimms.enumerated()), id: \.offset) { idx, d in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(d.bank).font(.callout.weight(.medium))
                            Spacer()
                            if let st = d.status {
                                Text(st).font(.caption2)
                                    .foregroundStyle(st.uppercased() == "OK" ? .green : .secondary)
                            }
                        }
                        if let size = d.sizeText { row("容量", size) }
                        if let type = d.type { row("类型", type) }
                        if let mt = d.speedMTs { row("等效速率", "\(mt) MT/s") }
                        if let v = d.manufacturer {
                            row("厂商", v)
                        } else if let c = d.manufacturerCode {
                            row("厂商", "\(c)（未识别）")
                        }
                        if let p = d.partNumber { row("物料号", p) }
                        if let sn = d.serial { row("序列号", sn) }
                    }
                    if idx < dimms.count - 1 { Divider().padding(.vertical, 4) }
                }
                Text("macOS 仅暴露以上静态字段；SPD 详细时序（tCL / tRCD / tRP / tRAS / tRFC / 命令速率）需第三方工具经 SMBus 直读，本页不做猜测。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 显卡

    private var graphicsSection: some View {
        HWSection(title: "显卡", icon: "display") {
            if s.gpus.isEmpty {
                Text("未检测到 GPU").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(s.gpus.enumerated()), id: \.element.name) { idx, g in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(g.displayName).font(.callout.weight(.medium))
                            Spacer()
                            Text(g.isIntegrated ? "集成" : "独立")
                                .font(.caption2)
                                .foregroundStyle(g.isIntegrated ? .teal : .purple)
                        }
                        row("厂商", g.vendor)
                        row("显存", g.vramTotalBytes > 0
                            ? String(format: "%.0f MB", g.vramTotalMB)
                            : "动态共享")
                        row("实时占用", String(format: "%.0f%%", g.utilization))
                        row("温度", g.temperatureC.map { String(format: "%.0f °C", $0) } ?? "–")
                        if let p = g.powerWatts {
                            row("功耗", Format.power(p))
                        } else if let l = g.powerLimitWatts {
                            row("功耗上限", Format.power(l))
                        } else {
                            row("功耗", "–")
                        }
                        row("频率", g.freqText)
                        if g.isIntegrated, let spec = cpu.spec,
                           let base = spec.igpuBaseMHz, let max = spec.igpuMaxMHz {
                            row("标称频率", "\(Format.gpuFreq(base)) ~ \(Format.gpuFreq(max))")
                        }
                    }
                    if idx < s.gpus.count - 1 { Divider().padding(.vertical, 4) }
                }
                Text("独显频率/占用为驱动实时数据；核显实时频率需安装 SuperStateKext 驱动（见「工具」页），未安装时显示「待机」。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 显示器
            if !hw.displays.isEmpty {
                Divider().padding(.vertical, 4)
                ForEach(Array(hw.displays.enumerated()), id: \.offset) { _, d in
                    HStack {
                        Text(d.type ?? "显示器").font(.callout.weight(.medium))
                        Spacer()
                        Text(d.resolution ?? "–").font(.caption.monospaced())
                    }
                }
            }
        }
    }

    // MARK: 行布局

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.monospaced()).lineLimit(1).truncationMode(.tail)
        }
    }
}

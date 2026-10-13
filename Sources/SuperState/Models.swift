import Foundation

// MARK: - GPU 快照（核显 / 独显分别建模）

struct GPUSnapshot {
    var name: String = ""
    var vendor: String = ""
    var isIntegrated: Bool = true       // true=核显 false=独显
    var available: Bool = false

    // 占用率（0-100）
    var utilization: Double = 0
    // 显存使用量 / 总量（字节）
    var vramUsedBytes: UInt64 = 0
    var vramTotalBytes: UInt64 = 0
    // 温度：免授权 SMC 可读（°C）
    var temperatureC: Double? = nil
    // 功耗：独显=SMC PG0R 导轨功率（免授权）；核显=SMC PCPG（免授权，断电时 0）
    var powerWatts: Double? = nil
    // 功耗上限（SMC PG0C，免授权；老硬件无实时功耗时显示功率限制，单位 W）
    var powerLimitWatts: Double? = nil
    // 频率（MHz）：老硬件/核显可能为 nil
    var freqMhz: Double? = nil

    var vramUsedMB: Double { Double(vramUsedBytes) / 1_048_576.0 }
    var vramTotalMB: Double { Double(vramTotalBytes) / 1_048_576.0 }
    var vramPercent: Double {
        guard vramTotalBytes > 0 else { return 0 }
        return min(100, Double(vramUsedBytes) / Double(vramTotalBytes) * 100)
    }
    var displayName: String {
        isIntegrated ? "核显 · \(name)" : "独显 · \(name)"
    }
    /// 菜单栏用型号简称："NVIDIA GeForce GT 650M"→"GT 650M"，"Intel HD Graphics 4000"→"HD 4000"
    var shortModel: String {
        let words = name.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return name }
        return words.suffix(2).joined(separator: " ")
    }
    /// GPU 频率显示：读不到（深度待机）时显示"待机"而非"–"
    var freqText: String {
        freqMhz.map { Format.gpuFreq($0) } ?? "待机"
    }
}

// MARK: - 风扇快照

struct FanSnapshot {
    var id: String = ""        // F0Ac / F1Ac
    var name: String = ""      // 左风扇 / 右风扇
    var rpm: Double = 0
}

// MARK: - CPU 核心/模块温度

struct CoreTemp {
    var label: String
    var tempC: Double
}

// MARK: - 进程信息

struct ProcInfo {
    var pid: Int32 = 0
    var cpu: Double = 0
    var memBytes: UInt64 = 0
    var name: String = ""
}

// MARK: - 系统整体快照

struct SystemSnapshot {
    var timestamp: Date = Date()

    // CPU
    var cpuUsage: Double = 0
    var cpuCoreUsages: [Double] = []            // 每个逻辑 CPU（超线程）占用率
    var cpuFreqMhz: Double? = nil               // 标称(免授权) 或 实时(管理员) 频率 MHz
    var cpuPowerWatts: Double? = nil        // CPU 核心功率（SMC PCPC 免授权；管理员模式 powermetrics 覆盖）
    var packagePowerWatts: Double? = nil    // 英特尔整机功率 CPUs+GT+SA（SMC PCPT 免授权；管理员模式 powermetrics 覆盖）
    var dramPowerWatts: Double? = nil       // 内存(DRAM)功率（kext RAPL，仅装驱动后可用）
    var cpuTempC: Double? = nil             // 免授权 SMC
    var cpuCoreTemps: [CoreTemp] = []       // 免授权 SMC 各核心/模块温度
    var sensorTemps: [SensorTemp] = []      // 全量温度传感器（iFan 口径，功能页展示）
    var cpuThermalLevel: Int = 0           // sysctl 0-255
    var gpuThermalLevel: Int = 0

    // 内存
    var memTotalBytes: UInt64 = 0
    var memUsedBytes: UInt64 = 0
    var memPressurePercent: Double = 0
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
    var memActiveBytes: UInt64 = 0      // 活跃
    var memWiredBytes: UInt64 = 0       // 联动
    var memCompressedBytes: UInt64 = 0  // 压缩

    // 进程 / 线程 / 句柄（系统总量）
    var processCount: Int = 0
    var threadCount: Int = 0
    var fileCount: Int = 0

    // 磁盘
    var diskTotalBytes: UInt64 = 0
    var diskFreeBytes: UInt64 = 0
    var diskReadBytesPerSec: UInt64 = 0
    var diskWriteBytesPerSec: UInt64 = 0

    // 网络
    var netUpBytesPerSec: UInt64 = 0
    var netDownBytesPerSec: UInt64 = 0
    var netUpTotalBytes: UInt64 = 0
    var netDownTotalBytes: UInt64 = 0

    // 其他
    var uptimeSeconds: TimeInterval = 0
    var batteryTempC: Double? = nil
    var fans: [FanSnapshot] = []
    var topProcesses: [ProcInfo] = []
    var gpus: [GPUSnapshot] = []

    var memUsedPercent: Double {
        guard memTotalBytes > 0 else { return 0 }
        return Double(memUsedBytes) / Double(memTotalBytes) * 100
    }
    /// 活跃内存占用率（活跃 / 总内存）：状态面板内存小卡片进度条与变色依据
    var memActivePercent: Double {
        guard memTotalBytes > 0 else { return 0 }
        return Double(memActiveBytes) / Double(memTotalBytes) * 100
    }
    var diskUsedPercent: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return Double(diskTotalBytes - diskFreeBytes) / Double(diskTotalBytes) * 100
    }
    /// 真正的整机功耗 = 英特尔封装（核心+核显GT+SA）+ 独显（两者都可得时）
    var totalPowerWatts: Double? {
        guard let pkg = packagePowerWatts,
              let dgpu = gpus.first(where: { !$0.isIntegrated }),
              let dp = dgpu.powerWatts else { return nil }
        return pkg + dp
    }
}

// MARK: - 历史曲线数据（环形缓冲）

final class HistoryStore {
    static let shared = HistoryStore()
    let capacity = 300

    private(set) var cpu: [Double] = []
    private(set) var mem: [Double] = []
    private(set) var netUp: [Double] = []
    private(set) var netDown: [Double] = []
    // 每个 GPU 一条曲线，下标与 gpus 快照顺序一致
    private(set) var gpuUtil: [[Double]] = []
    private(set) var timestamps: [Date] = []

    func append(_ s: SystemSnapshot) {
        timestamps.append(s.timestamp)
        cpu.append(s.cpuUsage)
        mem.append(s.memUsedPercent)
        netUp.append(Double(s.netUpBytesPerSec))
        netDown.append(Double(s.netDownBytesPerSec))

        if gpuUtil.count != s.gpus.count {
            gpuUtil = s.gpus.map { _ in [] }
        }
        for i in 0..<s.gpus.count {
            gpuUtil[i].append(s.gpus[i].utilization)
        }
        // 裁剪
        while timestamps.count > capacity {
            timestamps.removeFirst()
            cpu.removeFirst()
            mem.removeFirst()
            netUp.removeFirst()
            netDown.removeFirst()
            for i in 0..<gpuUtil.count { gpuUtil[i].removeFirst() }
        }
    }

    func reset() {
        timestamps.removeAll()
        cpu.removeAll()
        mem.removeAll()
        netUp.removeAll()
        netDown.removeAll()
        gpuUtil.removeAll()
    }
}

// MARK: - 字节 / 频率格式化

enum Format {
    /// GPU 频率紧凑格式（带单位）：< 1000MHz 用 MHz，否则用 GHz；无数据返回 "–"
    static func gpuFreq(_ mhz: Double?) -> String {
        guard let mhz, mhz > 0 else { return "–" }
        if mhz < 1000 { return String(format: "%.0fMHz", mhz) }
        return String(format: "%.2fGHz", mhz / 1000)
    }

    static func bytes(_ v: UInt64) -> String {
        let f = Double(v)
        switch f {
        case 0..<1024: return String(format: "%.0f B", f)
        case 1024..<(1024 * 1024): return String(format: "%.1f KB", f / 1024)
        case (1024 * 1024)..<(1024 * 1024 * 1024): return String(format: "%.1f MB", f / 1_048_576)
        default: return String(format: "%.2f GB", f / 1_073_741_824)
        }
    }

    static func rate(_ v: UInt64) -> String {
        bytes(v) + "/s"
    }

    /// 功率智能单位：按设置 0=自动（<1W 毫瓦）/1=始终瓦/2=始终毫瓦
    static func power(_ w: Double) -> String {
        switch Settings.powerUnitMode {
        case 1: return w < 100 ? String(format: "%.1f W", w) : String(format: "%.0f W", w)
        case 2: return String(format: "%.0f mW", w * 1000)
        default:
            if w < 1 { return String(format: "%.0f mW", w * 1000) }
            if w < 100 { return String(format: "%.1f W", w) }
            return String(format: "%.0f W", w)
        }
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let d = total / 86400
        let h = (total % 86400) / 3600
        let m = (total % 3600) / 60
        if d > 0 { return "\(d)天\(h)小时" }
        if h > 0 { return "\(h)小时\(m)分" }
        return "\(m)分"
    }
}

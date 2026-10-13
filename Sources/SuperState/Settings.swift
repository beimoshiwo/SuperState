import Foundation

/// 全局配置（UserDefaults）：监控哪些参数、显示在哪
enum Settings {

    private static let d = UserDefaults.standard

    // MARK: - 菜单栏显示项

    static var barShowCPU: Bool {
        get { d.object(forKey: "bar.cpu") as? Bool ?? true }
        set { d.set(newValue, forKey: "bar.cpu") }
    }
    /// CPU 功耗监控（SMC PCPC，CPU 核心功率，免授权）
    static var barShowCPUPower: Bool {
        get { d.object(forKey: "bar.cpupower") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.cpupower") }
    }
    /// 英特尔整机功耗监控（SMC PCPT，CPU+核显+SA 合并功率，免授权）
    /// 兼容旧键：此前「CPU / 整机功耗」开关开启过的用户迁移为整机功耗开启
    static var barShowPackagePower: Bool {
        get { d.object(forKey: "bar.pkgpower") as? Bool ?? (d.object(forKey: "bar.cpupower") as? Bool ?? false) }
        set { d.set(newValue, forKey: "bar.pkgpower") }
    }
    /// 真正的整机功耗（英特尔封装 + 独显导轨功率，免授权）
    static var barShowTotalPower: Bool {
        get { d.object(forKey: "bar.totalpower") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.totalpower") }
    }
    /// CPU 温度（免授权 SMC）
    static var barShowCPUTemp: Bool {
        get { d.object(forKey: "bar.cputemp") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.cputemp") }
    }
    /// CPU 频率（标称免授权；管理员模式显示实时睿频）
    static var barShowCPUFreq: Bool {
        get { d.object(forKey: "bar.cpufreq") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.cpufreq") }
    }
    /// 核显频率（部分平台提供；老硬件可能无数据）
    /// 兼容旧键：若用户此前勾选过合并的「GPU 频率」，迁移为两项均开
    static var barShowIGPUFreq: Bool {
        get { d.object(forKey: "bar.igpufreq") as? Bool ?? (d.object(forKey: "bar.gpufreq") as? Bool ?? false) }
        set { d.set(newValue, forKey: "bar.igpufreq") }
    }
    /// 独显频率（免授权实时，IOAccelerator PerformanceStatistics）
    static var barShowDGPUFreq: Bool {
        get { d.object(forKey: "bar.dgpufreq") as? Bool ?? (d.object(forKey: "bar.gpufreq") as? Bool ?? false) }
        set { d.set(newValue, forKey: "bar.dgpufreq") }
    }
    /// 内存压力（活动监视器同款绿色指示）
    static var barShowMemPressure: Bool {
        get { d.object(forKey: "bar.mempressure") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.mempressure") }
    }
    /// 进程数（libproc）
    static var barShowProcess: Bool {
        get { d.object(forKey: "bar.process") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.process") }
    }
    /// 线程数（libproc 逐进程累加）
    static var barShowThread: Bool {
        get { d.object(forKey: "bar.thread") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.thread") }
    }
    /// 句柄数（kern.num_files）
    static var barShowFile: Bool {
        get { d.object(forKey: "bar.file") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.file") }
    }
    /// 独显显存占用（免授权）
    static var barShowVRAM: Bool {
        get { d.object(forKey: "bar.vram") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.vram") }
    }
    /// 风扇转速（免授权）
    static var barShowFans: Bool {
        get { d.object(forKey: "bar.fans") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.fans") }
    }
    static var barShowMem: Bool {
        get { d.object(forKey: "bar.mem") as? Bool ?? true }
        set { d.set(newValue, forKey: "bar.mem") }
    }
    /// 独显占用率（菜单栏显示"独显 x%"）
    static var barShowDGPU: Bool {
        get { d.object(forKey: "bar.dgpu") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.dgpu") }
    }
    /// 核显占用率（菜单栏显示"核显 x%"）
    static var barShowIGPU: Bool {
        get { d.object(forKey: "bar.igpu") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.igpu") }
    }
    /// 独显温度（免授权 SMC）
    static var barShowDGPUTemp: Bool {
        get { d.object(forKey: "bar.dgputemp") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.dgputemp") }
    }
    /// 核显温度（免授权 SMC）
    static var barShowIGPUTemp: Bool {
        get { d.object(forKey: "bar.igputemp") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.igputemp") }
    }
    /// 独显实时功耗（SMC PG0R 导轨功率，免授权）
    static var barShowDGPUPower: Bool {
        get { d.object(forKey: "bar.dgpupower") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.dgpupower") }
    }
    /// 核显实时功耗（kext RAPL PP1 / SMC PCPG）
    static var barShowIGPUPower: Bool {
        get { d.object(forKey: "bar.igpupower") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.igpupower") }
    }
    /// 电池温度
    static var barShowBattery: Bool {
        get { d.object(forKey: "bar.battery") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.battery") }
    }
    static var barShowNet: Bool {
        get { d.object(forKey: "bar.net") as? Bool ?? true }
        set { d.set(newValue, forKey: "bar.net") }
    }
    static var barShowDisk: Bool {
        get { d.object(forKey: "bar.disk") as? Bool ?? false }
        set { d.set(newValue, forKey: "bar.disk") }
    }
    /// 紧凑模式：C12% M62% ↑1.2M ↓3.4M（默认开）
    static var compactBar: Bool {
        get { d.object(forKey: "bar.compact") as? Bool ?? true }
        set { d.set(newValue, forKey: "bar.compact") }
    }

    // MARK: - 面板显示项（状态面板始终展示全部模块，设置项已废弃）

    /// 功率单位：0=自动（<1W 毫瓦）、1=始终瓦、2=始终毫瓦
    static var powerUnitMode: Int {
        get { d.object(forKey: "power.unit") as? Int ?? 0 }
        set { d.set(newValue, forKey: "power.unit") }
    }

    static var panelShowGPU: Bool {
        get { d.object(forKey: "panel.gpu") as? Bool ?? true }
        set { d.set(newValue, forKey: "panel.gpu") }
    }
    /// GPU 占用率曲线（面板概览区，核显/独显两条）
    static var panelShowGPUCurves: Bool {
        get { d.object(forKey: "panel.gpucurves") as? Bool ?? true }
        set { d.set(newValue, forKey: "panel.gpucurves") }
    }
    static var panelShowProcesses: Bool {
        get { d.object(forKey: "panel.proc") as? Bool ?? true }
        set { d.set(newValue, forKey: "panel.proc") }
    }
    static var panelShowDiskIO: Bool {
        get { d.object(forKey: "panel.diskio") as? Bool ?? true }
        set { d.set(newValue, forKey: "panel.diskio") }
    }

    // MARK: - 紧凑数值格式

    /// 网速紧凑格式：1.2M / 340K / 8B
    static func compactRate(_ v: UInt64) -> String {
        let f = Double(v)
        if f >= 1_073_741_824 { return String(format: "%.1fG", f / 1_073_741_824) }
        if f >= 1_048_576 { return String(format: "%.1fM", f / 1_048_576) }
        if f >= 1024 { return String(format: "%.0fK", f / 1024) }
        return String(format: "%.0fB", f)
    }
}

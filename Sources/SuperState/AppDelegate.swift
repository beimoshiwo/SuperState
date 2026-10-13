import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selfcheck") {
            SelfCheck.run()
            NSApp.terminate(nil)
            return
        }

        Alerts.shared.requestPermission()
        Monitor.shared.start()
        StatusItemController.shared.setup()
        // 后台一次性采集静态硬件信息（供「硬件参数」页展示）
        MemoryProbe.shared.load()
        HardwareInfo.shared.load()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 退出前恢复系统自动风扇（手动控扇的安全兜底，防止残留低转速过热）
    func applicationWillTerminate(_ notification: Notification) {
        FeaturesView.restoreAuto()
    }
}

// 自检模式：采集一轮指标并打印，用于编译后冒烟验证
enum SelfCheck {
    static func run() {
        // 第一帧用于建立 CPU/网络/磁盘差分基线
        _ = SystemMetrics.cpuUsage()
        _ = SystemMetrics.memory()
        _ = SystemMetrics.disk()
        _ = SystemMetrics.diskIO()
        _ = SystemMetrics.network()
        Thread.sleep(forTimeInterval: 1.2)

        var s = SystemSnapshot()
        s.cpuUsage = SystemMetrics.cpuUsage()
        let mem = SystemMetrics.memory()
        s.memTotalBytes = mem.total
        s.memUsedBytes = mem.used
        s.memPressurePercent = mem.pressure
        s.swapUsedBytes = mem.swapUsed
        s.swapTotalBytes = mem.swapTotal
        s.memActiveBytes = mem.active
        s.memWiredBytes = mem.wired
        s.memCompressedBytes = mem.compressed
        let disk = SystemMetrics.disk()
        s.diskTotalBytes = disk.total
        s.diskFreeBytes = disk.free
        let io = SystemMetrics.diskIO()
        s.diskReadBytesPerSec = io.readPerSec
        s.diskWriteBytesPerSec = io.writePerSec
        let net = SystemMetrics.network()
        s.netUpBytesPerSec = net.upPerSec
        s.netDownBytesPerSec = net.downPerSec
        s.uptimeSeconds = SystemMetrics.uptime()
        s.cpuThermalLevel = ThermalMetrics.cpuThermalLevel()
        s.gpuThermalLevel = ThermalMetrics.gpuThermalLevel()
        s.batteryTempC = HardwareProbe.batteryTemperatureC()
        s.gpus = HardwareProbe.enumerateGPUs()
        s.topProcesses = SystemMetrics.topProcesses(6)
        s.processCount = SystemMetrics.processCount()
        s.threadCount = SystemMetrics.threadCount()
        s.fileCount = SystemMetrics.fileCount()
        MemoryProbe.shared.loadSync()

        let f = { (v: UInt64) -> String in Format.bytes(v) }
        print("== SuperState SelfCheck ==")
        print("CPU 占用: \(String(format: "%.1f", s.cpuUsage))%  热级 \(s.cpuThermalLevel)")
        print("内存: 已用 \(f(s.memUsedBytes)) / \(f(s.memTotalBytes)) (\(String(format: "%.1f", s.memUsedPercent))%)  压力 \(String(format: "%.1f", s.memPressurePercent))%  Swap \(f(s.swapUsedBytes))")
        print("磁盘: \(f(s.diskFreeBytes)) 可用 / \(f(s.diskTotalBytes))  读 \(f(s.diskReadBytesPerSec))/s 写 \(f(s.diskWriteBytesPerSec))/s")
        print("网络: ↑\(f(s.netUpBytesPerSec))/s ↓\(f(s.netDownBytesPerSec))/s")
        print("电池温度: \(s.batteryTempC.map { String(format: "%.1f", $0) } ?? "N/A") °C")
        print("开机时长: \(Format.uptime(s.uptimeSeconds))")
        print("GPU 数量: \(s.gpus.count)")
        for (i, g) in s.gpus.enumerated() {
            let kind = g.isIntegrated ? "核显" : "独显"
            let freq = g.freqMhz.map { String(format: "%.0fMHz", $0) } ?? "–"
            let limit = g.powerLimitWatts.map { Format.power($0) } ?? "–"
            print("  GPU\(i): [\(kind)] \(g.name) 占用 \(String(format: "%.1f", g.utilization))%  频率 \(freq)  功耗上限 \(limit)  显存 \(String(format: "%.0f", g.vramUsedMB))/\(String(format: "%.0f", g.vramTotalMB))MB  可用=\(g.available)")
        }
        // SMC 直读独显功耗上限与实时功耗（运行期内由 Monitor 每秒填充，此处验证读取通道）
        let limitW = SmcClient.shared?.readGPUPowerLimitW()
        let railW = SmcClient.shared?.readGPURailPowerW()
        print("独显功耗: 实时 \(railW.map { Format.power($0) } ?? "–")（SMC PG0R） · 上限 \(limitW.map { Format.power($0) } ?? "–")（SMC PG0C）")
        print("Top 进程:")
        for p in s.topProcesses {
            print("  \(p.pid) \(String(format: "%.1f", p.cpu))% \(f(p.memBytes)) \(p.name)")
        }
        let cpu = CPUInfo.shared
        print("CPU: \(cpu.brand)  内核 \(cpu.physicalCores) / 逻辑处理器 \(cpu.logicalCpus)  封装 \(cpu.packageType)")
        print("频率: 基础 \(String(format: "%.2f", cpu.baseFreqMHz / 1000))GHz  睿频 \(cpu.turboMHz.map { String(format: "%.2f GHz", $0 / 1000) } ?? "–")  核显最大 \(cpu.igpuMaxMHz.map { String(format: "%.0f MHz", $0) } ?? "–")  虚拟化 \(cpu.virtualization ? "支持" : "不支持")  缓存 \(cpu.cacheText)")
        let smc = SmcClient.shared
        print("功率（免授权 SMC）: CPU 核心 \(smc?.readCPUCorePowerW().map { Format.power($0) } ?? "–") · 整机 \(smc?.readPackageTotalPowerW().map { Format.power($0) } ?? "–") · 核显 \(smc?.readIGPUPowerW().map { Format.power($0) } ?? "–")")
        // kext（安装驱动后免授权）：逐核实时频率 + RAPL 各域功率
        let kx = KextMetrics.shared
        if kx.isAvailable {
            if let f = kx.readFreqMHz() {
                let cores = f.map { String(format: "%.0f", $0) }.joined(separator: "/")
                print("kext 实时频率: [\(cores)] MHz（均值 \(String(format: "%.0f", f.reduce(0,+)/Double(f.count)))）")
            }
            _ = kx.readPower()          // 首采样（建立差分基线）
            Thread.sleep(forTimeInterval: 0.6)
            let kp = kx.readPower()     // 差分出实时功率
            print("kext RAPL 功率: 整机 \(kp.packageW.map { Format.power($0) } ?? "–") · CPU核心 \(kp.cpuCoreW.map { Format.power($0) } ?? "–") · 核显 \(kp.gpuW.map { Format.power($0) } ?? "–") · DRAM \(kp.dramW.map { Format.power($0) } ?? "–")")
            if let gf = kx.readIGPUFreqMHz() {
                print("kext 核显实时频率: \(String(format: "%.0f", gf)) MHz")
            } else {
                print("kext 核显实时频率: 不支持/不可读（界面显示「待机」）")
            }
        } else {
            print("kext: 未加载（安装硬件监控驱动后可免密码读实时频率与各域功率）")
        }
        print("进程/线程/句柄: \(s.processCount) / \(s.threadCount) / \(s.fileCount)")
        // 全量温度传感器（iFan 口径）
        let keys = TempSensors.discoverKeys()
        print("温度传感器（共 \(keys.count) 个）:")
        for st in TempSensors.readAll(keys: keys) {
            print("  \(st.key)  \(st.label)  \(String(format: "%.1f°C", st.tempC))")
        }
        if let m = MemoryProbe.shared.info {
            print("内存: \(m.type ?? "–") \(m.speedMTs.map { "\($0) MT/s" } ?? "–")  \(m.slotText)")
        }
        print("== SelfCheck DONE ==")
    }
}

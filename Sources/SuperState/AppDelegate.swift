import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selfcheck") {
            SelfCheck.run()
            NSApp.terminate(nil)
            return
        }

        // 隐藏 CLI：被 osascript 以管理员身份重执行时运行风扇写入，完成后直接退出。
        // 必须用 exit() 而非 NSApp.terminate()——后者会触发 applicationWillTerminate
        // 的恢复自动逻辑，把刚设置的手动模式又改回去。
        if let idx = CommandLine.arguments.firstIndex(of: "--fan") {
            FanCLI.run(Array(CommandLine.arguments[(idx + 1)...]))
            return   // FanCLI 内部 exit()，不会到达这里
        }

        Alerts.shared.requestPermission()
        Monitor.shared.start()
        StatusItemController.shared.setup()
        GlobalHotkeyManager.shared.register()   // 系统级全局热键（⌘M 打开主界面 / ⌘⌥P 状态面板 / ⌘⌥F 网速悬浮窗）
        observeSleepWake()                      // 睡眠/唤醒期间暂停 kext 读取（GPU 电源态 churn 护栏）
        // 后台一次性采集静态硬件信息（供「硬件参数」页展示）
        MemoryProbe.shared.load()
        HardwareInfo.shared.load()
    }

    /// 睡眠/唤醒观察：系统睡眠期间 + 唤醒后过渡窗口内暂停 kext 硬件读取。
    /// 原因：本机 OCLP 3.0 内测版 GPU 驱动补丁不成熟，休眠→唤醒时 GPU 电源态剧烈切换，
    /// 方法 3（iGPU MMIO）的 TOCTOU 竞态在此窗口暴露最大。暂停只影响 kext 读数
    /// （界面降级为 SMC/标称值兜底），SMC 温度/风扇/功耗等免授权通道不受影响。
    private func observeSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            KextMetrics.shared.setSleeping(true)
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            KextMetrics.shared.setSleeping(false)
            KextMetrics.shared.extendWakeSettle(5)   // 等 GPU 驱动重初始化完成再恢复读 MMIO
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 退出前恢复系统自动风扇（手动控扇的安全兜底，防止残留低转速过热）。
    /// 必须同步等待：SMC 写通道受权限保护，可能要弹一次管理员授权框；
    /// 异步链会在 App 退出时被杀掉。取消/失败时发通知提醒用户。
    func applicationWillTerminate(_ notification: Notification) {
        let (ok, msg) = SmcFanWriter.shared.restoreAutoSync()
        if !ok {
            Alerts.shared.postNow(title: "风扇仍处于手动模式",
                                  body: msg ?? "退出时未能恢复系统自动风扇，重启电脑或重新打开 SuperState 可恢复。")
        }
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
            for d in m.dimms {
                print("  SPD \(d.bank): \(d.sizeText ?? "–") \(d.type ?? "–") \(d.speedMTs.map { "\($0) MT/s" } ?? "–")  厂商 \(d.manufacturer ?? d.manufacturerCode ?? "–")  物料号 \(d.partNumber ?? "–")  状态 \(d.status ?? "–")")
            }
        }
        print("== SelfCheck DONE ==")
    }
}

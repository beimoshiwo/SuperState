import Foundation
import Combine

/// 采集调度器：每秒聚合一次全系统快照
final class Monitor: ObservableObject {

    static let shared = Monitor()

    @Published var snapshot = SystemSnapshot()

    private var timer: Timer?
    /// 全量温度传感器键表（启动时发现一次后缓存）
    private var sensorKeys: [String] = []

    func start() {
        guard timer == nil else { return }
        tick()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        var s = SystemSnapshot()
        s.timestamp = Date()

        s.cpuUsage = SystemMetrics.cpuUsage()
        s.cpuCoreUsages = SystemMetrics.cpuUsagePerCore()
        let nominalFreq = SystemMetrics.cpuFreqNominalMHz()
        if nominalFreq > 0 { s.cpuFreqMhz = nominalFreq }

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
        s.netUpTotalBytes = net.upTotal
        s.netDownTotalBytes = net.downTotal

        s.uptimeSeconds = SystemMetrics.uptime()
        s.cpuThermalLevel = ThermalMetrics.cpuThermalLevel()
        s.gpuThermalLevel = ThermalMetrics.gpuThermalLevel()
        s.gpus = HardwareProbe.enumerateGPUs()
        s.topProcesses = SystemMetrics.topProcesses(6)
        s.processCount = SystemMetrics.processCount()
        s.threadCount = SystemMetrics.threadCount()
        s.fileCount = SystemMetrics.fileCount()

        // 免授权 SMC：CPU / GPU 温度、风扇、电池温度
        let smc = SmcClient.shared
        s.cpuTempC = smc?.readTemp(SensorMap.cpuMain)
        s.cpuCoreTemps = SensorMap.cpuCores.compactMap { key in
            guard let t = smc?.readTemp(key) else { return nil }
            return CoreTemp(label: key, tempC: t)
        }
        // 全量温度传感器（功能页 iFan 视图用；键表启动时发现一次后缓存）
        if sensorKeys.isEmpty { sensorKeys = TempSensors.discoverKeys() }
        if !sensorKeys.isEmpty { s.sensorTemps = TempSensors.readAll(keys: sensorKeys) }
        // 电池温度：优先 SMC，其次 ioreg
        s.batteryTempC = smc?.readTemp(SensorMap.battery) ?? HardwareProbe.batteryTemperatureC()
        // 风扇
        s.fans = SensorMap.fans.enumerated().compactMap { idx, key in
            guard let rpm = smc?.readFanRpm(key) else { return nil }
            let name = idx == 0 ? "左风扇" : "右风扇"
            return FanSnapshot(id: key, name: name, rpm: rpm)
        }
        // GPU 温度归属：核显=TG0P，独显=TG1D/TG0D
        if let igpuIdx = s.gpus.firstIndex(where: { $0.isIntegrated }) {
            s.gpus[igpuIdx].temperatureC = smc?.readTemp(SensorMap.gpuIntegrated)
            // 核显实时功率（SMC PCPG，免授权；独显模式下核显断电读 0）
            s.gpus[igpuIdx].powerWatts = smc?.readIGPUPowerW()
        }
        if let dgpuIdx = s.gpus.firstIndex(where: { !$0.isIntegrated }) {
            for key in SensorMap.gpuDiscrete {
                if let t = smc?.readTemp(key) {
                    s.gpus[dgpuIdx].temperatureC = t
                    break
                }
            }
            // 独显实时功耗（SMC PG0R 导轨功率，免授权，实测随负载动态变化）
            if let p = smc?.readGPURailPowerW() { s.gpus[dgpuIdx].powerWatts = p }
            // 独显功耗上限（SMC PG0C，免授权）
            s.gpus[dgpuIdx].powerLimitWatts = smc?.readGPUPowerLimitW()
        }

        // 免授权功率导轨（SMC）：PCPT≈整机功耗(CPUs+GT+SA)、PCPC=CPU 核心功率
        s.packagePowerWatts = smc?.readPackageTotalPowerW()
        s.cpuPowerWatts = smc?.readCPUCorePowerW()

        // kext（安装驱动后免授权，优先于 SMC）：逐核实时频率 + RAPL 各域功率
        let kext = KextMetrics.shared
        if kext.isAvailable {
            if let f = kext.readAverageFreqMHz() { s.cpuFreqMhz = f }
            let kp = kext.readPower()
            if let v = kp.packageW { s.packagePowerWatts = v }
            if let v = kp.cpuCoreW { s.cpuPowerWatts = v }
            if let v = kp.dramW { s.dramPowerWatts = v }
            if let v = kp.gpuW, let idx = s.gpus.firstIndex(where: { $0.isIntegrated }) {
                s.gpus[idx].powerWatts = v   // 核显 GT 真实功率（RAPL PP1）
            }
            // 核显实时频率（免授权，kext 读图形 MMIO 的 RPSTAT1）
            if let gf = kext.readIGPUFreqMHz(),
               let idx = s.gpus.firstIndex(where: { $0.isIntegrated }) {
                s.gpus[idx].freqMhz = gf
            }
        }

        // 管理员模式：powermetrics 的功耗与实时频率优先覆盖免授权值（为 nil 时保留免授权数据）
        if ThermalMetrics.shared.adminEnabled {
            ThermalMetrics.shared.refresh()
            if let p = ThermalMetrics.shared.cpuPowerW { s.cpuPowerWatts = p }
            if let p = ThermalMetrics.shared.packagePowerW { s.packagePowerWatts = p }
            if let f = ThermalMetrics.shared.cpuFreqMhz { s.cpuFreqMhz = f }
            // Apple Silicon 若提供独立 GPU 功耗/频率，归属给当前最活跃的 GPU
            if let gpuPower = ThermalMetrics.shared.gpuPowerW,
               let active = s.gpus.max(by: { $0.utilization < $1.utilization }),
               let idx = s.gpus.firstIndex(where: { $0.name == active.name }) {
                s.gpus[idx].powerWatts = gpuPower
            }
            if let gpuFreq = ThermalMetrics.shared.gpuFreqMhz {
                // Intel 平台 powermetrics 输出的是核显 GT 频率，优先归属核显
                if let idx = s.gpus.firstIndex(where: { $0.isIntegrated }) {
                    s.gpus[idx].freqMhz = gpuFreq
                } else if let active = s.gpus.max(by: { $0.utilization < $1.utilization }),
                          let idx = s.gpus.firstIndex(where: { $0.name == active.name }) {
                    s.gpus[idx].freqMhz = gpuFreq
                }
            }
        }

        snapshot = s
        HistoryStore.shared.append(s)
    }
}

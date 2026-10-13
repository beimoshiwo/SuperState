import Foundation

/// 温度 / 功耗采集：
/// - 免 root：sysctl 热级别、电池温度（ioreg）
/// - 管理员模式（可选）：powermetrics 持续采样 CPU/GPU 功耗与温度
///
/// Intel 平台实测输出（macOS 26）：
///   - 功耗: "Intel energy model derived package power (CPUs+GT+SA): 20.15W"（合并功耗）
///   - 温度: smc 采样器 "CPU die temperature: 91.34 C"
///   - NVIDIA 老卡不提供独立 GPU 功耗/温度，界面如实标注"硬件不支持"
final class ThermalMetrics {

    static let shared = ThermalMetrics()
    private init() {}

    private let logPath = "/tmp/superstate_powermetrics.log"
    private(set) var adminEnabled = false
    private(set) var adminError: String?

    // 最近一次解析结果
    private(set) var cpuPowerW: Double?          // Apple Silicon: CPU Power (mW)
    private(set) var gpuPowerW: Double?          // Apple Silicon: GPU Power (mW)
    private(set) var packagePowerW: Double?      // Intel: package power (W)
    private(set) var cpuTempC: Double?
    private(set) var gpuTempC: Double?
    private(set) var cpuFreqMhz: Double?      // 实时 CPU 平均频率（powermetrics，管理员）
    private(set) var gpuFreqMhz: Double?      // 实时 GPU 频率（部分平台提供）

    // MARK: - 免 root 数据

    /// CPU 热级别（sysctl machdep.xcpm.cpu_thermal_level，0-255，越高越热）
    static func cpuThermalLevel() -> Int {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("machdep.xcpm.cpu_thermal_level", &v, &size, nil, 0) == 0 {
            return Int(v)
        }
        return 0
    }

    static func gpuThermalLevel() -> Int {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("machdep.xcpm.gpu_thermal_level", &v, &size, nil, 0) == 0 {
            return Int(v)
        }
        return 0
    }

    // MARK: - 管理员模式（powermetrics）

    func enable(completion: @escaping (Bool, String?) -> Void) {
        // 启动脚本随应用携带（Contents/Resources/superstate_start.sh），
        // 内部以 setsid（start_new_session）常驻 powermetrics，避免被授权进程退出时连带终止。
        guard let url = Bundle.main.url(forResource: "superstate_start", withExtension: "sh") else {
            DispatchQueue.main.async { completion(false, "启动脚本缺失") }
            return
        }
        let script = "do shell script \"/bin/sh '\(url.path)'\" with administrator privileges"
        runAppleScript(script) { [weak self] ok, err in
            guard let self else {
                DispatchQueue.main.async { completion(false, "实例不可用") }
                return
            }
            // 统一回主队列：adminEnabled 会被 UI / Monitor 读取，@State 更新也必须在主线程
            DispatchQueue.main.async {
                if ok {
                    self.adminEnabled = true
                    self.adminError = nil
                    completion(true, nil)
                } else {
                    self.adminError = err
                    completion(false, err)
                }
            }
        }
    }

    func disable(completion: @escaping (Bool, String?) -> Void) {
        // 免授权清理：用户权限精确结束 powermetrics（对 root 进程可能失败，忽略）。
        // 若有残留，下次开启管理员模式时启动脚本会先 pkill -x 清理，对系统无影响。
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            task.arguments = ["-x", "powermetrics"]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                // 忽略失败，保证退出不阻塞
            }
            DispatchQueue.main.async {
                self.adminEnabled = false
                completion(true, nil)
            }
        }
    }

    private func runAppleScript(_ source: String, completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = false
            var message: String?
            if let osa = NSAppleScript(source: source) {
                var errorInfo: NSDictionary?
                osa.executeAndReturnError(&errorInfo)
                if let err = errorInfo {
                    message = (err[NSAppleScript.errorMessage] as? String) ?? "授权失败或已取消"
                } else {
                    ok = true
                }
            } else {
                message = "AppleScript 创建失败"
            }
            DispatchQueue.main.async { completion(ok, message) }
        }
    }

    /// 解析日志尾部，提取功耗与温度（兼容 Apple Silicon 与 Intel 两种格式）
    func refresh() {
        guard adminEnabled,
              let content = try? String(contentsOfFile: logPath, encoding: .utf8) else { return }
        let tail = String(content.suffix(60_000))

        // Apple Silicon 格式
        cpuPowerW = parse(tail, pattern: #"CPU Power:\s+([0-9]+)\s+mW"#).map { $0 / 1000.0 }
        gpuPowerW = parse(tail, pattern: #"GPU Power:\s+([0-9]+)\s+mW"#).map { $0 / 1000.0 }
        // Intel 格式：合并功耗（CPU+核显+SA），单位 W
        packagePowerW = parse(tail, pattern: #"derived package power \(CPUs\+GT\+SA\):\s+([0-9.]+)W"#)
        if packagePowerW == nil {
            packagePowerW = parse(tail, pattern: #"Package Power:\s+([0-9]+)\s+mW"#).map { $0 / 1000.0 }
        }

        // 温度
        cpuTempC = parse(tail, pattern: #"CPU die temperature:\s+([0-9.]+)\s+C"#)
        gpuTempC = parse(tail, pattern: #"GPU die temperature:\s+([0-9.]+)\s+C"#)
        if cpuTempC == nil { cpuTempC = parse(tail, pattern: #"CPU temperature:\s+([0-9.]+)\s+C"#) }
        if gpuTempC == nil { gpuTempC = parse(tail, pattern: #"GPU temperature:\s+([0-9.]+)\s+C"#) }

        // 实时频率（MHz）：优先系统整体平均，其次 CPU 平均
        cpuFreqMhz = parse(tail, pattern: #"System Average frequency as fraction of nominal:\s+[0-9.]+%\s+\(([0-9.]+)\s*Mhz\)"#)
        if cpuFreqMhz == nil {
            cpuFreqMhz = parse(tail, pattern: #"CPU Average frequency as fraction of nominal:\s+[0-9.]+%\s+\(([0-9.]+)\s*Mhz\)"#)
        }
        // GPU 频率（仅部分平台输出；Intel 平台为核显 GT 频率，独显断电时为 0/nil）
        gpuFreqMhz = parse(tail, pattern: #"(?:GPU|GT)[^\n]*?\(([0-9.]+)\s*Mhz\)"#)
        if gpuFreqMhz == nil {
            gpuFreqMhz = parse(tail, pattern: #"GPU HW active frequency:\s+([0-9.]+)\s*M[Hh]z"#)
        }
        if let f = gpuFreqMhz, f <= 0 { gpuFreqMhz = nil }
    }

    private func parse(_ text: String, pattern: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return Double(ns.substring(with: m.range(at: 1)))
    }
}

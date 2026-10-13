import Foundation
import IOKit

// MARK: - 免授权硬件读数（经 SuperStateKext 内核扩展）
//
// 一旦 kext 安装并加载，App 通过其 UserClient 免密码读取：
//   - 逐逻辑 CPU 实时频率（MSR 0x198）
//   - RAPL 能量计数（差分得 整机/CPU 核心/核显 GT/DRAM 实时功率）
//
// kext 未安装/未加载时，isAvailable = false，App 自动回退到 SMC / 管理员模式。

final class KextMetrics {

    static let shared = KextMetrics()

    private var conn: io_connect_t = 0
    private(set) var isAvailable = false

    // RAPL 上一采样（能量计数 + 时间戳），用于差分求功率
    private struct RaplSample {
        var pkg: UInt32 = 0
        var pp0: UInt32 = 0
        var pp1: UInt32 = 0
        var dram: UInt32 = 0
        var validMask: UInt32 = 0
        var esuShift: UInt32 = 0
        var at: UInt64 = 0
    }
    private var lastRapl: RaplSample?

    private static let kMethodReadFreq: UInt32 = 0
    private static let kMethodReadRAPL: UInt32 = 1
    private static let kMethodGetVersion: UInt32 = 2
    private static let kMethodReadGPUFreq: UInt32 = 3

    /// App 期望的驱动接口版本（与 Kext/SuperStateKext.cpp 的 kSuperStateKextInterfaceVersion 对应）
    static let expectedKextVersion: UInt32 = 5
    private static let kRaplStructSize = 6 * 4        // pkg/pp0/pp1/dram/esuShift/validMask（6×UInt32）

    private init() {
        open()
    }

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    private func open() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("SuperStateKext"))
        guard service != 0 else { isAvailable = false; return }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        isAvailable = (kr == KERN_SUCCESS)
        if !isAvailable { conn = 0 }
    }

    // MARK: - 驱动状态（未安装 / 旧版 / 就绪）

    enum Status: Equatable {
        case notInstalled
        case outdated(UInt32)   // 检测到旧版（版本号）
        case ready
    }

    /// 读取运行中驱动的接口版本；调用失败返回 nil
    func readKextVersion() -> UInt32? {
        guard isAvailable else { return nil }
        var out = [UInt8](repeating: 0, count: 4)
        var outSize = out.count
        let kr = out.withUnsafeMutableBytes { buf in
            IOConnectCallStructMethod(conn, Self.kMethodGetVersion, nil, 0, buf.baseAddress, &outSize)
        }
        guard kr == KERN_SUCCESS else { return nil }
        return out.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    var status: Status {
        guard isAvailable else { return .notInstalled }
        // 旧版驱动没有版本握手方法，读不到版本 → 视为旧版（需更新）
        guard let v = readKextVersion() else { return .outdated(0) }
        return v >= Self.expectedKextVersion ? .ready : .outdated(v)
    }

    /// 重新探测（安装/卸载后调用）
    func refresh() {
        closeConnection()
        open()
    }

    /// 主动断开与 kext 的用户客户端连接（安装/卸载前调用，否则 kext 被占用无法卸载替换）
    func closeConnection() {
        if conn != 0 { IOServiceClose(conn); conn = 0 }
        isAvailable = false
    }

    // MARK: - 实时频率（逐逻辑 CPU）

    /// 方法 0：kext 读「当前 CPU」的 MSR，返回 (cpu 编号, 频率 MHz)
    private func callReadFreq() -> (cpu: Int, mhz: Double)? {
        var out = [UInt8](repeating: 0, count: 8)   // uint32 cpu + uint32 mhz
        var outSize = out.count
        let kr = out.withUnsafeMutableBytes { buf in
            IOConnectCallStructMethod(conn, Self.kMethodReadFreq, nil, 0, buf.baseAddress, &outSize)
        }
        guard kr == KERN_SUCCESS else { return nil }
        return out.withUnsafeBytes { buf in
            (Int(buf.load(fromByteOffset: 0, as: UInt32.self)),
             Double(buf.load(fromByteOffset: 4, as: UInt32.self)))
        }
    }

    /// 绑定当前线程到指定逻辑 CPU（THREAD_AFFINITY_POLICY，Intel 平台支持）
    private func setAffinity(_ tag: Int32, on thread: thread_t) -> Bool {
        var policy = thread_affinity_policy_data_t(affinity_tag: tag)
        let kr = withUnsafeMutablePointer(to: &policy) { ptr in
            thread_policy_set(thread, 4 /*THREAD_AFFINITY_POLICY*/,
                              UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: Int32.self), 1)
        }
        return kr == KERN_SUCCESS
    }

    /// 返回每个逻辑 CPU 的实时频率 MHz（kext 逐核读取，App 轮流绑定采集）
    func readFreqMHz() -> [Double]? {
        guard isAvailable else { return nil }
        let ncpu = max(1, ProcessInfo.processInfo.activeProcessorCount)
        var byId: [Int: Double] = [:]
        let thread = mach_thread_self()
        defer {
            _ = setAffinity(0, on: thread)   // tag 0 = 解除绑定
        }
        for tag in 1...Int32(max(32, ncpu)) {
            if byId.count >= ncpu { break }
            guard setAffinity(tag, on: thread) else { continue }
            if let r = callReadFreq(), r.mhz > 0, r.mhz < 10000 {
                byId[r.cpu] = r.mhz
            }
        }
        // 亲和性映射可能只覆盖部分核：解除绑定后补采，让线程自然漂移收集更多核
        if byId.count < ncpu {
            _ = setAffinity(0, on: thread)
            for _ in 0..<(ncpu * 4) where byId.count < ncpu {
                if let r = callReadFreq(), r.mhz > 0, r.mhz < 10000 {
                    byId[r.cpu] = r.mhz
                }
            }
        }
        guard !byId.isEmpty else { return nil }
        return byId.keys.sorted().map { byId[$0]! }
    }

    /// 所有核心平均实时频率 MHz（菜单栏/概览用）
    func readAverageFreqMHz() -> Double? {
        guard let f = readFreqMHz() else { return nil }
        return f.reduce(0, +) / Double(f.count)
    }

    // MARK: - 核显实时频率（只读图形 MMIO，免授权）

    /// 方法 3：kext 读核显图形 MMIO 的 RPSTAT1，返回实时频率 MHz；
    /// 不支持/不可读时返回 nil（界面显示"待机"）。fail-safe。
    func readIGPUFreqMHz() -> Double? {
        guard isAvailable else { return nil }
        var out = [UInt8](repeating: 0, count: 8)   // uint32 mhz + uint32 supported
        var outSize = out.count
        let kr = out.withUnsafeMutableBytes { buf in
            IOConnectCallStructMethod(conn, Self.kMethodReadGPUFreq, nil, 0, buf.baseAddress, &outSize)
        }
        guard kr == KERN_SUCCESS else { return nil }
        return out.withUnsafeBytes { buf in
            let supported = buf.load(fromByteOffset: 4, as: UInt32.self)
            guard supported == 1 else { return nil }
            return Double(buf.load(fromByteOffset: 0, as: UInt32.self))
        }
    }

    // MARK: - RAPL 功率（差分）

    struct Power {
        var packageW: Double?
        var cpuCoreW: Double?
        var gpuW: Double?      // 核显 GT
        var dramW: Double?
    }

    /// 读取并差分出实时功率（W）；首次调用返回 nil（需要两次采样）
    func readPower() -> Power {
        var p = Power()
        guard isAvailable else { return p }
        var out = [UInt8](repeating: 0, count: Self.kRaplStructSize)
        var outSize = out.count
        let kr = out.withUnsafeMutableBytes { buf in
            IOConnectCallStructMethod(conn, Self.kMethodReadRAPL, nil, 0, buf.baseAddress, &outSize)
        }
        guard kr == KERN_SUCCESS else { return p }

        var sample = RaplSample()
        out.withUnsafeBytes { buf in
            sample.pkg  = buf.load(fromByteOffset: 0,  as: UInt32.self)
            sample.pp0  = buf.load(fromByteOffset: 4,  as: UInt32.self)
            sample.pp1  = buf.load(fromByteOffset: 8,  as: UInt32.self)
            sample.dram = buf.load(fromByteOffset: 12, as: UInt32.self)
            sample.esuShift  = buf.load(fromByteOffset: 16, as: UInt32.self)
            sample.validMask = buf.load(fromByteOffset: 20, as: UInt32.self)
        }
        sample.at = DispatchTime.now().uptimeNanoseconds

        defer { lastRapl = sample }
        guard let last = lastRapl else { return p }
        let dt = Double(sample.at - last.at) / 1_000_000_000.0
        guard dt > 0 else { return p }

        // 能量单位 = 1 / 2^esuShift 焦耳
        let unit = 1.0 / Double(1 << min(Int(sample.esuShift), 31))

    func watts(_ cur: UInt32, _ prev: UInt32) -> Double {
        // 必须用 UInt32 回绕减法（&-），绝不能用受检的 Int32 减法：
        // 计数器回绕或 kext 重载清零后 prev 可能远大于 cur，Int32 减法会溢出 → SIGILL 崩溃
        let d = cur &- prev
        return Double(d) * unit / dt
    }

        if sample.validMask & 1 != 0 { p.packageW = watts(sample.pkg, last.pkg) }
        if sample.validMask & 2 != 0 { p.cpuCoreW = watts(sample.pp0, last.pp0) }
        if sample.validMask & 4 != 0 { p.gpuW = watts(sample.pp1, last.pp1) }
        if sample.validMask & 8 != 0 { p.dramW = watts(sample.dram, last.dram) }
        return p
    }

    // MARK: - 安装（一次性管理员授权）

    /// 将 AppleScript / shell 返回的原始（多为英文）错误本地化为简体中文。
    /// `do shell script … with administrator privileges` 报错是英文的
    /// （如 "User canceled." / "System Policy: … blocked" / "execution error: …"），
    /// 这里做模式匹配给出中文提示；未知错误保留原文加中文前缀，便于排查。
    private static func localizeKextError(_ raw: String?) -> String {
        let r = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty { return "操作未完成或已取消。" }
        let lower = r.lowercased()
        if lower.contains("user canceled") {
            return "已取消：你没有输入密码（授权已被取消）。"
        }
        if lower.contains("blocked") || lower.contains("system policy") {
            return "系统安全策略阻止了安装。请打开 系统设置 → 隐私与安全性，点「仍要允许」，再重试（只需一次）。"
        }
        if lower.contains("not permitted") || lower.contains("permission denied") || lower.contains("elevated privileges") {
            return "权限不足：安装内核扩展需要管理员密码，请确认密码后重试。"
        }
        if lower.contains("kext") && (lower.contains("load") || lower.contains("invalid") || lower.contains("fail")) {
            return "驱动已复制但无法加载：\(r)。请到 系统设置 → 隐私与安全性 中手动允许该驱动后重试。"
        }
        // 兜底：保留原始信息，加中文前缀便于排查
        return "安装失败：\(r)"
    }

    /// 运行随 App 携带的安装脚本，安装并加载 kext（需一次密码）
    static func install(completion: @escaping (Bool, String?) -> Void) {
        guard let url = Bundle.main.url(forResource: "install_kext", withExtension: "sh") else {
            DispatchQueue.main.async { completion(false, "安装脚本缺失") }
            return
        }
        // 先断开用户客户端，避免旧 kext 被占用导致卸载/替换失败
        shared.closeConnection()
        let script = "do shell script \"/bin/sh '\(url.path)'\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = false
            var message: String?
            if let osa = NSAppleScript(source: script) {
                var err: NSDictionary?
                osa.executeAndReturnError(&err)
                if let e = err {
                    message = Self.localizeKextError(e[NSAppleScript.errorMessage] as? String)
                } else {
                    ok = true
                }
            } else {
                message = "AppleScript 创建失败"
            }
            DispatchQueue.main.async {
                if ok { shared.refresh() }   // 重新探测 kext 是否已加载
                completion(ok, message)
            }
        }
    }

    /// 卸载驱动（需一次管理员授权）：卸载内核扩展 + 删除文件与开机自载服务
    static func uninstall(completion: @escaping (Bool, String?) -> Void) {
        guard let url = Bundle.main.url(forResource: "uninstall_kext", withExtension: "sh") else {
            DispatchQueue.main.async { completion(false, "卸载脚本缺失") }
            return
        }
        shared.closeConnection()
        let script = "do shell script \"/bin/sh '\(url.path)'\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            var ok = false
            var message: String?
            if let osa = NSAppleScript(source: script) {
                var err: NSDictionary?
                osa.executeAndReturnError(&err)
                if let e = err {
                    message = Self.localizeKextError(e[NSAppleScript.errorMessage] as? String)
                } else {
                    ok = true
                }
            } else {
                message = "AppleScript 创建失败"
            }
            DispatchQueue.main.async {
                if ok { shared.refresh() }
                completion(ok, message)
            }
        }
    }
}

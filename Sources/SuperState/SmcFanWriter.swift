import Foundation
import IOKit

// MARK: - 风扇写入器（直连优先，权限不足时回退管理员通道）

/// 背景（2026-10-14 本机实测，AppleSMC 3.1.9 / macOS 26）：
/// - 读取通道（GetKeyInfo / ReadKey）免授权正常；
/// - **写入通道（WriteKey）对非特权进程一律返回 kIOReturnNotPrivileged (0xE00002C1)**，
///   与连接类型无关——这正是此前风扇控制"装饰化"的真因；
/// - 因此写入采用两级策略：先免授权直连（老系统可用），被拒后再以管理员身份
///   重执行本 App 二进制的隐藏 CLI（`--fan`），与「管理员模式」同源（osascript）。
final class SmcFanWriter {

    static let shared = SmcFanWriter()
    private init() {}

    private let queue = DispatchQueue(label: "smc.fan.writer")
    private var pending: DispatchWorkItem?
    /// 已确认直连写入被权限门禁拒绝（本会话内粘性，避免每次徒劳直连）
    private var directBlocked = false

    /// 最近一次操作结果（UI 展示）
    private(set) var lastMessage: String = ""

    // MARK: - 对外接口

    /// 请求一次风扇状态应用（滑杆拖动高频调用会自动合并为一次执行）
    /// - Parameters:
    ///   - manual: true=手动模式，false=恢复系统自动
    ///   - targets: [(风扇下标, 目标转速 rpm)]，manual=false 时忽略
    func request(manual: Bool, targets: [(index: Int, rpm: Double)], completion: ((Bool, String?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let work = DispatchWorkItem {
                self.apply(manual: manual, targets: targets) { ok, msg in
                    DispatchQueue.main.async { completion?(ok, msg) }
                }
            }
            self.pending = work
            self.queue.asyncAfter(deadline: .now() + 0.25, execute: work)   // 拖动合并窗口
        }
    }

    /// 恢复系统自动风扇（退出兜底 / 安全看门狗用）
    func restoreAuto(completion: ((Bool, String?) -> Void)? = nil) {
        request(manual: false, targets: [], completion: completion)
    }

    /// 同步版：供 App 退出路径使用（阻塞至多 timeout 秒，给管理员授权框留出时间）。
    /// 异步链在退出时可能来不及跑完，且主线程等待时完成回调不能回主队列（会死锁），
    /// 因此这里直接在工作队列上执行并信号量等待。
    func restoreAutoSync(timeout: TimeInterval = 20) -> (Bool, String?) {
        let sem = DispatchSemaphore(value: 0)
        var result: (Bool, String?) = (false, nil)
        queue.async { [weak self] in
            self?.apply(manual: false, targets: []) { ok, msg in
                result = (ok, msg)
                sem.signal()
            }
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            return (false, "超时：未能恢复系统自动风扇")
        }
        return result
    }

    // MARK: - 实际执行

    private func apply(manual: Bool, targets: [(index: Int, rpm: Double)], completion: ((Bool, String?) -> Void)? = nil) {
        guard let smc = SmcClient.shared else {
            finish(false, "SMC 不可用", completion: completion)
            return
        }

        // 第一级：免授权直连
        if !directBlocked {
            let r = applyDirect(smc, manual: manual, targets: targets)
            if r.ok {
                finish(true, manual ? "已应用（免授权直连）" : "已恢复系统自动", completion: completion)
                return
            }
            if r.kr == kIOReturnNotPrivileged {
                directBlocked = true   // 本机写通道有权限门禁，后续直接走管理员通道
            } else {
                finish(false, "SMC 写入失败（kr=0x\(String(r.kr, radix: 16))）", completion: completion)
                return
            }
        }

        // 第二级：管理员身份重执行本 App 的隐藏 CLI
        let args = FanCLI.arguments(manual: manual, targets: targets)
        let (ok, output) = runPrivileged(args)
        if ok {
            finish(true, manual ? "已应用（管理员授权）" : "已恢复系统自动", completion: completion)
        } else {
            finish(false, output ?? "管理员授权失败或被取消", completion: completion)
        }
    }

    private func applyDirect(_ smc: SmcClient, manual: Bool, targets: [(index: Int, rpm: Double)]) -> (ok: Bool, kr: kern_return_t) {
        let modeResult = smc.setFanModeStatus(manual: manual)
        guard modeResult.ok else { return modeResult }
        guard manual else { return (true, KERN_SUCCESS) }
        for t in targets {
            let r = smc.setFanTargetStatus(t.index, rpm: t.rpm)
            guard r.ok else { return r }
        }
        return (true, KERN_SUCCESS)
    }

    /// 以管理员身份执行本 App 二进制（osascript，与 ThermalMetrics 管理员模式同模式）。
    /// Security Server 会缓存授权约 5 分钟，连续调节不会反复弹密码框。
    private func runPrivileged(_ args: [String]) -> (Bool, String?) {
        let exe = Bundle.main.executablePath ?? "/Applications/SuperState.app/Contents/MacOS/SuperState"
        let shellCmd = "'\(exe)' " + args.joined(separator: " ")
        let source = "do shell script \"\(shellCmd)\" with administrator privileges"
        var ok = false
        var message: String?
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            if let osa = NSAppleScript(source: source) {
                var errorInfo: NSDictionary?
                let desc = osa.executeAndReturnError(&errorInfo)
                if let err = errorInfo {
                    message = (err[NSAppleScript.errorMessage] as? String) ?? "授权失败或已取消"
                } else {
                    ok = true
                    message = desc.stringValue   // 直出 helper 的 stdout（"OK" / "FAIL: ..."）
                }
            } else {
                message = "AppleScript 创建失败"
            }
            sem.signal()
        }
        sem.wait()
        return (ok, message)
    }

    private func finish(_ ok: Bool, _ msg: String, completion: ((Bool, String?) -> Void)?) {
        lastMessage = msg
        // 回调在 writer 队列上执行；需要更新 UI 的调用方自行切主队列（request 已包装）
        completion?(ok, msg)
    }
}

// MARK: - 隐藏 CLI（被 osascript 以 root 重执行时运行，做完写入即退出）

/// 用法（由 SmcFanWriter 自动拼装，也可手动排障）：
///   SuperState --fan mode 1 target 0 4000 target 1 4000
///   SuperState --fan restore
/// stdout 输出 "OK" 或 "FAIL: 原因"；退出码 0=成功 1=失败 2=参数错误。
enum FanCLI {

    static func run(_ args: [String]) {
        setbuf(stdout, nil)   // 管道场景下必须关缓冲，否则 root helper 的输出丢失
        guard let smc = SmcClient.shared else {
            print("FAIL: SMC 不可用")
            exit(2)
        }
        var manual = false
        var targets: [(index: Int, rpm: Double)] = []
        var i = 0
        while i < args.count {
            switch args[i] {
            case "mode":
                guard i + 1 < args.count, let m = Int(args[i + 1]) else {
                    print("FAIL: mode 参数错误"); exit(2)
                }
                manual = (m != 0)
                i += 2
            case "target":
                guard i + 2 < args.count, let idx = Int(args[i + 1]), let rpm = Double(args[i + 2]) else {
                    print("FAIL: target 参数错误"); exit(2)
                }
                targets.append((idx, rpm))
                i += 3
            case "restore":
                manual = false
                targets = []
                i += 1
            default:
                print("FAIL: 未知参数 \(args[i])"); exit(2)
            }
        }

        var ok = smc.setFanModeStatus(manual: manual).ok
        if ok && manual {
            for t in targets {
                if !smc.setFanTargetStatus(t.index, rpm: t.rpm).ok { ok = false; break }
            }
        }
        print(ok ? "OK" : "FAIL: SMC 写入被拒绝")
        fflush(stdout)
        exit(ok ? 0 : 1)
    }

    /// 拼装 CLI 参数
    static func arguments(manual: Bool, targets: [(index: Int, rpm: Double)]) -> [String] {
        var args = ["--fan"]
        if manual {
            args.append("mode"); args.append("1")
            for t in targets {
                args.append("target"); args.append("\(t.index)"); args.append("\(Int(t.rpm))")
            }
        } else {
            args.append("restore")
        }
        return args
    }
}

// MARK: - 过热安全看门狗

/// 手动控扇期间的温度护栏：CPU/GPU 任一 ≥ 阈值即自动恢复系统自动模式（安全兜底，防过热）。
final class FanSafetyWatchdog {
    static let shared = FanSafetyWatchdog()
    private init() {}

    /// 触发温度（°C）：真实硬件持续 95°C 已属危险区，恢复自动让系统自行调速
    static let thresholdC = 95.0

    private var timer: DispatchSourceTimer?
    /// 看门狗是否活跃（UI 在进入手动/最大/自定义模式时开启，退出时关闭）
    var isActive: Bool { timer != nil }

    func start(onTrigger: @escaping (String) -> Void) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 10, repeating: 10)
        t.setEventHandler { [weak self] in
            guard let self, self.timer != nil else { return }
            let s = Monitor.shared.snapshot
            var hot: String?
            if let c = s.cpuTempC, c >= Self.thresholdC { hot = String(format: "CPU %.0f°C", c) }
            if let g = s.gpus.compactMap(\.temperatureC).max(), g >= Self.thresholdC {
                hot = hot.map { $0 + " · " } ?? ""
                hot = (hot ?? "") + String(format: "GPU %.0f°C", g)
            }
            if let hot {
                self.stop()
                SmcFanWriter.shared.restoreAuto()
                DispatchQueue.main.async { onTrigger("温度过高（\(hot)），已自动恢复系统风扇模式") }
            }
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

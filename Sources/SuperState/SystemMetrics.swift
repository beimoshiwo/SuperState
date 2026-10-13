import Foundation
import Darwin

/// 系统指标采集：CPU / 内存 / 磁盘 / 网络 / 进程
enum SystemMetrics {

    // MARK: - CPU 占用率（host_processor_info 差分）

    private static var lastIdle: UInt64?
    private static var lastTotal: UInt64 = 0

    static func cpuUsage() -> Double {
        var cpuCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let infoPtr = info else { return 0 }

        // 注意：必须用 UInt64 累加——8 个逻辑 CPU 的 tick 合计约 62 天就会溢出 UInt32，
        // 溢出后减法下溢会触发 Swift 陷阱（长 uptime 必现闪退）
        var idle: UInt64 = 0
        var total: UInt64 = 0
        let count = Int(infoCount) / Int(CPU_STATE_MAX)
        if count > 0 {
            let ptr = infoPtr.withMemoryRebound(to: processor_cpu_load_info.self, capacity: count) { $0 }
            for i in 0..<count {
                let t = ptr[i].cpu_ticks
                // tuple: (USER, SYSTEM, IDLE, NICE)
                idle += UInt64(t.2)
                total += UInt64(t.0) + UInt64(t.1) + UInt64(t.3) + UInt64(t.2)
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount * UInt32(MemoryLayout<integer_t>.size)))

        guard let lastIdleValue = lastIdle, lastTotal > 0 else {
            lastIdle = idle
            lastTotal = total
            return 0
        }
        // 防御计数器回绕
        let idleDelta = idle >= lastIdleValue ? idle - lastIdleValue : 0
        let totalDelta = total >= lastTotal ? total - lastTotal : 0
        lastIdle = idle
        lastTotal = total
        guard totalDelta > 0 else { return 0 }
        return max(0, min(100, 100.0 * (1.0 - Double(idleDelta) / Double(totalDelta))))
    }

    // MARK: - 每逻辑 CPU 占用率（host_processor_info 差分）

    private static var lastCoreIdle: [UInt64] = []
    private static var lastCoreTotal: [UInt64] = []

    /// 返回每个逻辑 CPU（超线程）的占用率 0-100，如四核八线程返回 8 个值
    static func cpuUsagePerCore() -> [Double] {
        var cpuCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let infoPtr = info else { return [] }

        let n = Int(infoCount) / Int(CPU_STATE_MAX)
        var idles = [UInt64]()
        var totals = [UInt64]()
        if n > 0 {
            let ptr = infoPtr.withMemoryRebound(to: processor_cpu_load_info.self, capacity: n) { $0 }
            for i in 0..<n {
                let t = ptr[i].cpu_ticks
                let idleTick = UInt64(t.2)
                let total = UInt64(t.0) + UInt64(t.1) + idleTick + UInt64(t.3)
                idles.append(idleTick)
                totals.append(total)
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount * UInt32(MemoryLayout<integer_t>.size)))

        var result = [Double]()
        if lastCoreIdle.count == n {
            for i in 0..<n {
                let dIdle = idles[i] >= lastCoreIdle[i] ? idles[i] - lastCoreIdle[i] : 0
                let dTotal = totals[i] >= lastCoreTotal[i] ? totals[i] - lastCoreTotal[i] : 0
                let u = dTotal > 0 ? max(0, min(100, 100.0 * (1.0 - Double(dIdle) / Double(dTotal)))) : 0
                result.append(u)
            }
        } else {
            result = Array(repeating: 0, count: n)
        }
        lastCoreIdle = idles
        lastCoreTotal = totals
        return result
    }

    // MARK: - CPU 标称频率（免授权 sysctl）

    /// CPU 标称最大频率（MHz），来自 hw.cpufrequency_max；实时睿频需管理员模式
    static func cpuFreqNominalMHz() -> Double {
        var hz: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.cpufrequency_max", &hz, &size, nil, 0) == 0, hz > 0 {
            return Double(hz) / 1_000_000.0
        }
        return 0
    }

    // MARK: - 内存

    static func memory() -> (total: UInt64, used: UInt64, pressure: Double, swapUsed: UInt64, swapTotal: UInt64,
                             active: UInt64, wired: UInt64, compressed: UInt64) {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return (total, 0, 0, 0, 0, 0, 0, 0)
        }
        let page = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let used = active + wired + compressed
        let pressure = memoryPressure()

        var swap: xsw_usage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsed = swap.xsu_used
            swapTotal = swap.xsu_total
        }
        return (total, used, pressure, swapUsed, swapTotal, active, wired, compressed)
    }

    /// 内核真实内存压力（0~100，与活动监视器"内存压力"图同源）。
    /// kern.memorystatus_level = 内核计算的可用内存百分比，取反即压力。
    /// 免授权；读取失败时回退为占用率估算。
    static func memoryPressure() -> Double {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0, (0...100).contains(level) {
            return Double(100 - level)
        }
        return 0
    }

    // MARK: - 进程 / 线程 / 句柄 总数

    /// 系统进程总数（libproc，免子进程）
    static func processCount() -> Int {
        Int(proc_listallpids(nil, 0))
    }

    /// 系统线程总数（libproc：逐进程 PROC_PIDTASKALLINFO 的 pti_threadnum 之和，免子进程）。
    /// 注：受保护进程读不到 threadinfo，计数为下限值；macOS 的 ps 无 nlwp 关键字，故不用 ps。
    static func threadCount() -> Int {
        let bufSize = 4096
        var pids = [Int32](repeating: 0, count: bufSize)
        let n = proc_listallpids(&pids, Int32(bufSize * MemoryLayout<Int32>.size))
        var total = 0
        for i in 0..<Int(n) {
            var info = proc_taskallinfo()
            if proc_pidinfo(pids[i], PROC_PIDTASKALLINFO, 0, &info,
                            Int32(MemoryLayout<proc_taskallinfo>.size)) > 0 {
                total += Int(info.ptinfo.pti_threadnum)
            }
        }
        return total
    }

    /// 系统打开的文件句柄总数（kern.num_files）
    static func fileCount() -> Int {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.num_files", &v, &size, nil, 0) == 0 { return Int(v) }
        return 0
    }

    // MARK: - 磁盘

    static func disk() -> (total: UInt64, free: UInt64) {
        var st = statfs()
        guard statfs("/", &st) == 0 else { return (0, 0) }
        let total = UInt64(st.f_blocks) * UInt64(st.f_bsize)
        let free = UInt64(st.f_bavail) * UInt64(st.f_bsize)
        return (total, free)
    }

    private static var lastDiskIO: (read: UInt64, write: UInt64)?
    private static var lastDiskTime: Date?

    /// 磁盘读写速率（IOBlockStorageDriver Statistics 差分）
    static func diskIO() -> (readPerSec: UInt64, writePerSec: UInt64) {
        let now = Date()
        var read: UInt64 = 0
        var write: UInt64 = 0

        let matching = IOServiceMatching("IOBlockStorageDriver")
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS {
            defer { IOObjectRelease(iter) }
            while true {
                let entry = IOIteratorNext(iter)
                if entry == 0 { break }
                defer { IOObjectRelease(entry) }
                if let stats = HardwareProbe.propertyDict(entry, "Statistics") {
                    if let b = stats["Bytes (Read)"] as? NSNumber { read += b.uint64Value }
                    if let b = stats["Bytes (Written)"] as? NSNumber { write += b.uint64Value }
                }
            }
        }

        guard let last = lastDiskIO, let lastTime = lastDiskTime else {
            lastDiskIO = (read, write)
            lastDiskTime = now
            return (0, 0)
        }
        let elapsed = now.timeIntervalSince(lastTime)
        lastDiskIO = (read, write)
        lastDiskTime = now
        guard elapsed > 0 else { return (0, 0) }
        let r = read >= last.read ? UInt64(Double(read - last.read) / elapsed) : 0
        let w = write >= last.write ? UInt64(Double(write - last.write) / elapsed) : 0
        return (r, w)
    }

    // MARK: - 网络

    private static var lastNet: (up: UInt64, down: UInt64)?
    private static var lastNetTime: Date?
    private static var netTotal: (up: UInt64, down: UInt64) = (0, 0)

    /// 汇总所有非 loopback 活跃接口的流量差分 → 上下行速率
    static func network() -> (upPerSec: UInt64, downPerSec: UInt64, upTotal: UInt64, downTotal: UInt64) {
        var up: UInt64 = 0
        var down: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return (0, 0, netTotal.up, netTotal.down)
        }
        defer { freeifaddrs(ifaddr) }

        var p = Optional(first)
        while let cur = p {
            defer { p = cur.pointee.ifa_next }
            let name = String(cString: cur.pointee.ifa_name)
            if name == "lo0" { continue }
            let flags = cur.pointee.ifa_flags
            if flags & UInt32(IFF_UP) == 0 { continue }
            if cur.pointee.ifa_addr.pointee.sa_family != UInt8(AF_LINK) { continue }
            if let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(d.ifi_ibytes)
                up += UInt64(d.ifi_obytes)
            }
        }

        netTotal = (up, down)
        let now = Date()
        guard let last = lastNet, let lastTime = lastNetTime else {
            lastNet = (up, down)
            lastNetTime = now
            return (0, 0, up, down)
        }
        let elapsed = now.timeIntervalSince(lastTime)
        lastNet = (up, down)
        lastNetTime = now
        guard elapsed > 0 else { return (0, 0, up, down) }
        let upRate = up >= last.up ? UInt64(Double(up - last.up) / elapsed) : 0
        let downRate = down >= last.down ? UInt64(Double(down - last.down) / elapsed) : 0
        return (upRate, downRate, up, down)
    }

    // MARK: - 开机时间

    static func uptime() -> TimeInterval {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            return Date().timeIntervalSince1970 - Double(tv.tv_sec)
        }
        return 0
    }

    // MARK: - Top 进程（ps 按 CPU 排序）

    /// Top 进程（ps 按 CPU 排序）
    static func topProcesses(_ limit: Int) -> [ProcInfo] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-arcwwwxo", "pid=,%cpu=,%mem=,rss=,comm=", "-r"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var result: [ProcInfo] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rss = Double(parts[3]) else { continue }
            let name = parts.dropFirst(4).joined(separator: " ")
            result.append(ProcInfo(pid: pid, cpu: cpu, memBytes: rss > 0 ? UInt64(rss * 1024) : 0, name: String(name)))
            if result.count >= limit { break }
        }
        return result
    }
}

import Foundation
import IOKit

// MARK: - 电池信息（IORegistry AppleSmartBattery，免授权）

struct HWBatteryInfo {
    var cycleCount: Int = 0          // 循环次数
    var maxCapacity: Int = 0         // 当前最大容量 mAh
    var designCapacity: Int = 0      // 设计容量 mAh
    var currentCapacity: Int = 0     // 当前电量 mAh
    var temperatureC: Double = 0     // 温度（ioreg 为 K×100）
    var voltageMV: Int = 0           // 电压 mV
    var isCharging: Bool = false
    var fullyCharged: Bool = false
    var externalConnected: Bool = false
    var manufacturer: String?
    var serial: String?

    /// 电池健康度（当前最大容量 / 设计容量）
    var healthPercent: Double? {
        guard designCapacity > 0, maxCapacity > 0 else { return nil }
        return min(100, Double(maxCapacity) / Double(designCapacity) * 100)
    }
}

// MARK: - 存储 / 显示 / 网络（system_profiler 一次性解析）

struct HWStorageInfo {
    var capacity: UInt64 = 0
    var available: UInt64 = 0
    var mount: String?
    var fileSystem: String?
    var deviceName: String?
    var mediumType: String?   // SSD / HDD
    var busProtocol: String?     // SATA / USB / NVMe ...
}

struct HWDisplayInfo {
    var chipset: String?      // 图形芯片
    var type: String?         // Built-In Retina LCD ...
    var resolution: String?   // 2880 x 1800 Retina
    var isMain: Bool = false
}

struct HWNetworkInfo {
    var type: String?         // AirPort / Ethernet
    var bsd: String?          // en0
    var ipv4: [String] = []
}

/// 硬件参数探测器：应用启动时后台采集一次（system_profiler 约 2~4 秒），结果缓存
final class HardwareInfo: ObservableObject {

    static let shared = HardwareInfo()

    @Published private(set) var battery: HWBatteryInfo?
    @Published private(set) var storages: [HWStorageInfo] = []
    @Published private(set) var displays: [HWDisplayInfo] = []
    @Published private(set) var networks: [HWNetworkInfo] = []
    @Published private(set) var loaded = false

    private init() {}

    func load() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let battery = Self.readBattery()
            let (storages, displays, networks) = Self.readSystemProfiler()
            DispatchQueue.main.async {
                self?.battery = battery
                self?.storages = storages
                self?.displays = displays
                self?.networks = networks
                self?.loaded = true
            }
        }
    }

    // MARK: - 电池（IORegistry）

    private static func readBattery() -> HWBatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var b = HWBatteryInfo()
        b.cycleCount = propInt(service, "CycleCount")
        b.maxCapacity = propInt(service, "MaxCapacity")
        b.designCapacity = propInt(service, "DesignCapacity")
        b.currentCapacity = propInt(service, "CurrentCapacity")
        b.voltageMV = propInt(service, "Voltage")
        // 温度为 K×100
        if let t = propDouble(service, "Temperature") { b.temperatureC = t / 100.0 - 273.15 }
        b.isCharging = propBool(service, "IsCharging")
        b.fullyCharged = propBool(service, "FullyCharged")
        b.externalConnected = propBool(service, "ExternalConnected")
        b.manufacturer = propString(service, "Manufacturer")
        b.serial = propString(service, "Serial")
        return b
    }

    private static func propInt(_ s: io_registry_entry_t, _ key: String) -> Int {
        guard let v = propDouble(s, key) else { return 0 }
        return Int(v)
    }
    private static func propDouble(_ s: io_registry_entry_t, _ key: String) -> Double? {
        guard let p = IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        if let n = p as? NSNumber { return n.doubleValue }
        return nil
    }
    private static func propBool(_ s: io_registry_entry_t, _ key: String) -> Bool {
        guard let p = IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return false }
        if let b = p as? NSNumber { return b.boolValue }
        return false
    }
    private static func propString(_ s: io_registry_entry_t, _ key: String) -> String? {
        guard let p = IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        if let s = p as? String { return s }
        if let d = p as? Data { return String(data: d, encoding: .utf8) }
        return nil
    }

    // MARK: - 存储 / 显示 / 网络（system_profiler）

    private static func readSystemProfiler() -> ([HWStorageInfo], [HWDisplayInfo], [HWNetworkInfo]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPStorageDataType", "SPDisplaysDataType", "SPNetworkDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return ([], [], []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return ([], [], []) }

        var storages: [HWStorageInfo] = []
        var displays: [HWDisplayInfo] = []
        var networks: [HWNetworkInfo] = []
        var section = ""
        var curStorage: HWStorageInfo?
        var curChipset = ""
        var curDisplay: HWDisplayInfo?
        var curNetwork: HWNetworkInfo?

        func flushStorage() {
            if var s = curStorage {
                if s.mount == nil { return }  // 非挂载卷（如 EFI）跳过
                if s.deviceName == nil { s.deviceName = "存储卷" }
                storages.append(s)
            }
            curStorage = nil
        }
        func flushDisplay() {
            if let d = curDisplay {
                if d.type == nil { return }
                displays.append(d)
            }
            curDisplay = nil
        }
        func flushNetwork() {
            if let n = curNetwork {
                if n.bsd == nil { return }
                networks.append(n)
            }
            curNetwork = nil
        }

        for raw in text.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line == "Storage:" { flushStorage(); section = "storage"; continue }
            if line == "Displays:" { flushDisplay(); section = "display"; continue }
            if line == "Network:" { flushNetwork(); section = "network"; continue }
            if line == "Software:" || line == "Hardware:" { continue }

            switch section {
            case "storage":
                if line.hasPrefix("Capacity:") {
                    flushStorage()
                    var s = HWStorageInfo()
                    s.capacity = bytesInParens(line) ?? 0
                    curStorage = s
                } else if line.hasPrefix("Available:") {
                    curStorage?.available = bytesInParens(line) ?? 0
                } else if line.hasPrefix("Mount Point:") {
                    curStorage?.mount = value(line)
                } else if line.hasPrefix("File System:") {
                    curStorage?.fileSystem = value(line)
                } else if line.hasPrefix("Device Name:") {
                    curStorage?.deviceName = value(line)
                } else if line.hasPrefix("Medium Type:") {
                    curStorage?.mediumType = value(line)
                } else if line.hasPrefix("Protocol:") {
                    curStorage?.busProtocol = value(line)
                }
            case "display":
                if line.hasPrefix("Chipset Model:") {
                    flushDisplay()
                    curChipset = value(line)
                } else if line.hasPrefix("Display Type:") {
                    flushDisplay()
                    var d = HWDisplayInfo()
                    d.chipset = curChipset
                    d.type = value(line)
                    curDisplay = d
                } else if line.hasPrefix("Resolution:") {
                    curDisplay?.resolution = value(line)
                } else if line.hasPrefix("Main Display:") {
                    curDisplay?.isMain = value(line) == "Yes"
                }
            case "network":
                if line.hasPrefix("Type:") {
                    flushNetwork()
                    var n = HWNetworkInfo()
                    n.type = value(line)
                    curNetwork = n
                } else if line.hasPrefix("BSD Device Name:") {
                    curNetwork?.bsd = value(line)
                } else if line.hasPrefix("IPv4 Addresses:") {
                    curNetwork?.ipv4 = value(line).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                }
            default: break
            }
        }
        flushStorage(); flushDisplay(); flushNetwork()
        return (storages, displays, networks)
    }

    /// "Capacity: 62.34 GB (62,344,265,728 bytes)" → 62344265728
    private static func bytesInParens(_ line: String) -> UInt64? {
        guard let r = line.range(of: #"\(([\d,]+) bytes\)"#, options: .regularExpression) else { return nil }
        let inner = line[r].dropFirst().dropLast().replacingOccurrences(of: " bytes)", with: "").replacingOccurrences(of: ",", with: "")
        return UInt64(inner)
    }

    /// "Key: Value" → "Value"
    private static func value(_ line: String) -> String {
        String(line.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 系统静态信息（sysctl / IORegistry，免授权）

enum HWSystemInfo {
    /// 序列号（IOPlatformExpertDevice.IOPlatformSerialNumber）
    static var serial: String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "–" }
        defer { IOObjectRelease(service) }
        if let p = IORegistryEntryCreateCFProperty(service, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return p
        }
        return "–"
    }

    /// 主板 ID（board-id）
    static var boardId: String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "–" }
        defer { IOObjectRelease(service) }
        if let p = IORegistryEntryCreateCFProperty(service, "board-id" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return p
        }
        return "–"
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 系统构建号（kern.osversion，如 25G241）
    static var osBuild: String { CPUInfo.sysctlString("kern.osversion") }
    /// 内核版本（kern.osrelease）
    static var kernelVersion: String { CPUInfo.sysctlString("kern.osrelease") }
    /// 启动时间
    static var bootDate: Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            return Date(timeIntervalSince1970: Double(tv.tv_sec))
        }
        return nil
    }
}

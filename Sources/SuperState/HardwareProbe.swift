import Foundation
import IOKit

/// GPU 硬件探测：枚举 IOAccelerator，识别核显 / 独显，读取占用率与显存
enum HardwareProbe {

    /// 返回按 核显在前、独显在后 排序的 GPU 列表
    static func enumerateGPUs() -> [GPUSnapshot] {
        var result: [GPUSnapshot] = []
        let matching = IOServiceMatching("IOAccelerator")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return result
        }
        defer { IOObjectRelease(iter) }

        while true {
            let entry = IOIteratorNext(iter)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            result.append(readGPU(entry))
        }
        // 核显在前，独显在后
        result.sort { $0.isIntegrated && !$1.isIntegrated }
        return result
    }

    private static func readGPU(_ entry: io_registry_entry_t) -> GPUSnapshot {
        var snap = GPUSnapshot()

        let ioClass = propertyString(entry, "IOClass") ?? ""
        var model = propertyString(entry, "model") ?? ""
        // IOAccelerator 节点通常没有 model 属性（尤其 OCLP 环境），
        // 真实型号在 PCI 父设备（GFX0/IGPU）上，沿 parent 链向上找
        if model.isEmpty || model.lowercased().contains("accelerator") {
            model = parentModel(of: entry) ?? ""
        }
        snap.name = model.isEmpty ? ioClass : model
        let lower = (ioClass + " " + model).lowercased()
        if lower.contains("nv") || lower.contains("nvidia") || lower.contains("geforce") {
            snap.vendor = "NVIDIA"
            snap.isIntegrated = false
        } else if lower.contains("amd") || lower.contains("radeon") {
            snap.vendor = "AMD"
            snap.isIntegrated = false
        } else {
            snap.vendor = "Intel"
            snap.isIntegrated = true
        }

        // 显存总量（MB）
        if let v = propertyNumber(entry, "VRAM,totalMB") {
            snap.vramTotalBytes = UInt64(v.doubleValue) * 1_048_576
        }

        // 动态统计
        if let stats = propertyDict(entry, "PerformanceStatistics") {
            snap.available = true

            if let u = stats["Device Utilization % at cur p-state"] as? NSNumber {
                snap.utilization = u.doubleValue
            } else if let u = stats["Device Unit 0 Utilization %"] as? NSNumber {
                snap.utilization = u.doubleValue
            } else if let u = stats["Device Utilization %"] as? NSNumber {
                snap.utilization = u.doubleValue
            }

            if let b = stats["vramUsedBytes"] as? NSNumber {
                snap.vramUsedBytes = b.uint64Value
            } else if let b = stats["inUseVidMemoryBytes"] as? NSNumber {
                snap.vramUsedBytes = b.uint64Value
            }

            // GPU 核心频率（免授权）：
            // NVIDIA 驱动把实时核心时钟（Hz）放在名为 "GPU Core Utilization" 的字段里
            // （历史遗留的误导性命名，实测：GT 650M 空载 290~520MHz、满载 990MHz）。
            // Intel 核显无此字段，freqMhz 保持 nil（界面显示"–"）。
            if let hz = stats["GPU Core Utilization"] as? NSNumber {
                let mhz = hz.doubleValue / 1_000_000.0
                if mhz > 0, mhz < 5000 { snap.freqMhz = mhz }
            }
        }

        // 显存总量兜底：沿 parent 链（最多 3 级）查找，属性可能是二进制大端格式
        if snap.vramTotalBytes == 0 {
            var cur: io_registry_entry_t = entry
            var parent: io_registry_entry_t = 0
            var found = false
            for _ in 0..<3 {
                guard IORegistryEntryGetParentEntry(cur, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
                if let v = propertyNumber(parent, "VRAM,totalMB") {
                    snap.vramTotalBytes = UInt64(v.doubleValue) * 1_048_576
                    found = true
                }
                if found {
                    IOObjectRelease(parent)
                    if cur != entry { IOObjectRelease(cur) }
                    break
                }
                if cur != entry { IOObjectRelease(cur) }
                cur = parent
            }
            if !found && cur != entry { IOObjectRelease(cur) }
        }

        // 再兜底：空闲最大块近似显存总量
        if snap.vramTotalBytes == 0, let stats = propertyDict(entry, "PerformanceStatistics"),
           let free = stats["vramLargestFreeBytes"] as? NSNumber {
            snap.vramTotalBytes = free.uint64Value
        }

        return snap
    }

    /// 沿 parent 链（最多 5 级）查找第一个非空 "model" 属性（PCI 显示设备的真实型号）
    private static func parentModel(of entry: io_registry_entry_t) -> String? {
        var cur: io_registry_entry_t = entry
        for _ in 0..<5 {
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(cur, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            if cur != entry { IOObjectRelease(cur) }
            cur = parent
            if let m = propertyString(cur, "model") {
                let cleaned = m.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    IOObjectRelease(cur)
                    return cleaned
                }
            }
        }
        if cur != entry { IOObjectRelease(cur) }
        return nil
    }

    // MARK: - IORegistry 属性读取

    static func propertyString(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let prop = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let v = prop.takeRetainedValue()
        if let s = v as? String { return s }
        if let d = v as? Data { return String(data: d, encoding: .utf8) }
        return nil
    }

    static func propertyNumber(_ entry: io_registry_entry_t, _ key: String) -> NSNumber? {
        guard let prop = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let v = prop.takeRetainedValue()
        if let n = v as? NSNumber { return n }
        if let d = v as? Data {
            // 防御：超过 8 字节的二进制属性无法放入 UInt64，
            // 且移位量 >= 64 会触发移位溢出陷阱（SIGILL 闪退），直接按无数据跳过
            guard d.count <= 8 else { return nil }
            // 二进制小端无符号整数
            var value: UInt64 = 0
            for (i, b) in d.enumerated() {
                value |= UInt64(b) << (8 * i)
            }
            return NSNumber(value: value)
        }
        return nil
    }

    static func propertyDict(_ entry: io_registry_entry_t, _ key: String) -> [String: Any]? {
        guard let prop = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let v = prop.takeRetainedValue()
        return v as? [String: Any]
    }

    /// 电池温度（K×10 → °C），免 root
    static func batteryTemperatureC() -> Double? {
        let matching = IOServiceMatching("AppleSmartBattery")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }
        while true {
            let entry = IOIteratorNext(iter)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            if let v = propertyNumber(entry, "Temperature") {
                let kelvinTimes10 = v.doubleValue
                return kelvinTimes10 / 10.0 - 273.15
            }
        }
        return nil
    }
}

import Foundation

// MARK: - 内存静态信息（system_profiler 一次性解析，后台加载）

/// 内存条/颗粒信息：等效速率（MT/s）、代数、插槽或焊接
struct MemoryStaticInfo {
    var speedMTs: Int? = nil      // "Speed: 1600 MHz" → 1600 MT/s
    var type: String? = nil       // DDR3 / DDR4 / LPDDR4 ...
    var upgradeable: Bool = false // "Upgradeable Memory: Yes" → 插槽可升级
    var slotCount: Int = 0        // BANK 数量
    var slotSizeTexts: [String] = [] // 每条容量原文（如 "4 GB"）

    /// "焊接 · 2 槽位 4 GB + 4 GB" / "插槽（可升级） · 2 槽位 ..."
    var slotText: String {
        guard slotCount > 0 else { return "–" }
        let kind = upgradeable ? "插槽（可升级）" : "焊接"
        let sizes = slotSizeTexts.joined(separator: " + ")
        if sizes.isEmpty { return "\(kind) · \(slotCount) 槽位" }
        return "\(kind) · \(slotCount) 槽位 \(sizes)"
    }
}

/// 内存静态信息探测器：应用启动时后台解析一次（system_profiler 约 1~2 秒），结果缓存
final class MemoryProbe: ObservableObject {

    static let shared = MemoryProbe()

    @Published private(set) var info: MemoryStaticInfo?

    private init() {}

    func load() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let info = Self.readSystemProfiler()
            DispatchQueue.main.async { self?.info = info }
        }
    }

    /// 同步读取（--selfcheck 用；正常启动走异步 load()，避免阻塞 UI）
    func loadSync() {
        info = Self.readSystemProfiler()
    }

    /// 解析 system_profiler SPMemoryDataType：
    ///   Memory Slots:
    ///     ECC: Disabled
    ///     Upgradeable Memory: No
    ///       BANK 0/DIMM0:
    ///         Size: 4 GB
    ///         Type: DDR3
    ///         Speed: 1600 MHz
    private static func readSystemProfiler() -> MemoryStaticInfo {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPMemoryDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return MemoryStaticInfo() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return MemoryStaticInfo() }

        var info = MemoryStaticInfo()
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Upgradeable Memory:") {
                info.upgradeable = t.contains("Yes")
            } else if t.hasPrefix("Speed:") {
                // "Speed: 1600 MHz" → 1600
                let num = t.split(separator: " ").dropFirst().first.flatMap { Double($0) }
                if let num { info.speedMTs = Int(num) }
            } else if t.hasPrefix("Type:") {
                info.type = String(t.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("BANK") {
                info.slotCount += 1
            } else if t.hasPrefix("Size:") {
                // 保留原文（如 "4 GB"），避免 GB/GiB 换算歧义
                let text = String(t.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { info.slotSizeTexts.append(text) }
            }
        }
        return info
    }
}

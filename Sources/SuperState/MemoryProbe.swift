import Foundation

// MARK: - 内存静态信息（system_profiler 一次性解析，后台加载）

/// 单条内存（SPD 信息）：容量/类型/速率/厂商/物料号
/// 注：macOS 只暴露上述静态字段；详细时序（tCL/tRCD/tRP/tRAS/tRFC）不提供，需第三方工具直读 SMBus。
struct MemoryDIMM {
    var bank: String = ""          // "BANK 0/DIMM0"
    var sizeText: String? = nil    // 容量原文（如 "4 GB"）
    var type: String? = nil        // DDR3 / DDR4
    var speedMTs: Int? = nil       // 等效速率（1600 MT/s）
    var status: String? = nil      // OK
    var manufacturerCode: String? = nil // 原始厂商代码（如 "0x80AD"）
    var manufacturer: String? = nil     // 解码后的厂商名（SK Hynix）
    var partNumber: String? = nil       // 物料号（十六进制 ASCII 已解码）
    var serial: String? = nil
}

/// 内存静态信息：等效速率（MT/s）、代数、插槽或焊接
struct MemoryStaticInfo {
    var speedMTs: Int? = nil      // "Speed: 1600 MHz" → 1600 MT/s
    var type: String? = nil       // DDR3 / DDR4 / LPDDR4 ...
    var upgradeable: Bool = false // "Upgradeable Memory: Yes" → 插槽可升级
    var slotCount: Int = 0        // BANK 数量
    var slotSizeTexts: [String] = [] // 每条容量原文（如 "4 GB"）
    var eccEnabled: Bool? = nil   // "ECC: Disabled/Enabled"
    var dimms: [MemoryDIMM] = []  // 每槽位详细 SPD 信息（CPU-Z SPD 页）

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
        var curDimm: MemoryDIMM?
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("ECC:") {
                info.eccEnabled = t.contains("Enabled")
            } else if t.hasPrefix("Upgradeable Memory:") {
                info.upgradeable = t.contains("Yes")
            } else if t.hasPrefix("Speed:") {
                // "Speed: 1600 MHz" → 1600
                let num = t.split(separator: " ").dropFirst().first.flatMap { Double($0) }
                if let num {
                    if info.speedMTs == nil { info.speedMTs = Int(num) }
                    curDimm?.speedMTs = Int(num)
                }
            } else if t.hasPrefix("Type:") {
                let v = String(t.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
                if info.type == nil { info.type = v }
                curDimm?.type = v
            } else if t.hasPrefix("Status:") {
                curDimm?.status = String(t.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("Manufacturer:") {
                let code = String(t.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
                curDimm?.manufacturerCode = code
                curDimm?.manufacturer = Self.jedecVendor(code)
            } else if t.hasPrefix("Part Number:") {
                let raw = String(t.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
                curDimm?.partNumber = Self.decodeSPDString(raw)
            } else if t.hasPrefix("Serial Number:") {
                let v = String(t.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
                if v != "-" { curDimm?.serial = v }
            } else if t.hasPrefix("BANK") {
                // 新槽位开始：先收上一条
                if let d = curDimm { info.dimms.append(d) }
                curDimm = MemoryDIMM(bank: String(t.split(separator: ":").first ?? ""))
                info.slotCount += 1
            } else if t.hasPrefix("Size:") {
                // 保留原文（如 "4 GB"），避免 GB/GiB 换算歧义
                let text = String(t.split(separator: ":", maxSplits: 1).last ?? "").trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    info.slotSizeTexts.append(text)
                    curDimm?.sizeText = text
                }
            }
        }
        if let d = curDimm { info.dimms.append(d) }
        return info
    }

    /// SPD 厂商代码 → 厂商名（JEDEC bank1，仅收录常见厂商；未知返回 nil，界面显示原始代码）
    /// 例："0x80AD" → "SK Hynix"（0x80 = 无延续字节标志，后两字节为厂商 ID）
    static func jedecVendor(_ code: String) -> String? {
        let hex = code.hasPrefix("0x") ? String(code.dropFirst(2)) : code
        guard hex.count >= 2, !hex.contains(where: { !$0.isHexDigit }) else { return nil }
        switch String(hex.suffix(2)).uppercased() {
        case "AD": return "SK Hynix"
        case "CE": return "Samsung"
        case "2C": return "Micron"
        case "98": return "Kingston"
        case "C1": return "Qimonda"
        case "04": return "Fujitsu"
        case "83": return "Elpida"
        default: return nil
        }
    }

    /// SPD 字符串：十六进制 ASCII（如 "0x484D5433..."）解码为可读文本；
    /// 已是普通文本或解码出不可打印字符时原样返回。
    static func decodeSPDString(_ raw: String) -> String {
        let hex = raw.hasPrefix("0x") ? String(raw.dropFirst(2)) : raw
        guard !hex.isEmpty, hex.count % 2 == 0, hex.allSatisfy({ $0.isHexDigit }) else { return raw }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            bytes.append(UInt8(hex[i..<j], radix: 16) ?? 0x20)
            i = j
        }
        guard let s = String(bytes: bytes, encoding: .ascii),
              s.allSatisfy({ if let a = $0.asciiValue { return a >= 0x20 && a <= 0x7E } ; return false }) else { return raw }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? raw : trimmed
    }
}

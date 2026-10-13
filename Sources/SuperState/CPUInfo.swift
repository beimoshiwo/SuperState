import Foundation

// MARK: - CPU 规格数据库（Intel 官方参数，睿频/核显最大频率/插槽/TDP）
// macOS 的 sysctl 只暴露标称频率（hw.cpufrequency = 基础频率），睿频与核显最大动态频率
// 需查 Intel ARK；此处内置常见型号数据，未收录的型号显示"–"。

struct CPUSpec {
    var turboMHz: Double? = nil       // 最大睿频频率（单核）
    var igpuName: String? = nil       // 核显型号
    var igpuBaseMHz: Double? = nil    // 核显基础频率
    var igpuMaxMHz: Double? = nil     // 核显最大动态频率
    var tdpW: Double? = nil           // TDP
    var socket: String? = nil         // 封装/插槽（FCBGA1224 / FCPGA946 ...）
    var codename: String? = nil       // 架构代号
    var maxTempC: Double? = nil       // Tjunction
    var process: String? = nil        // 制程（22nm ...）
}

enum CPUSpecDB {

    /// 从品牌串提取型号（如 "Intel(R) Core(TM) i7-3615QM CPU @ 2.30GHz" → "i7-3615QM"）
    static func modelNumber(from brand: String) -> String? {
        let pattern = #"[iI][3579]-\d{4}[A-Za-z]{0,3}"#
        return brand.firstMatch(of: pattern)
    }

    /// 查规格；未收录返回 nil
    static func spec(forModel model: String) -> CPUSpec? {
        database[model.uppercased()]
    }

    // MARK: - 数据库（turbo=最大睿频，igpuMax=核显最大动态频率，单位 MHz）

    static let database: [String: CPUSpec] = {
        var d: [String: CPUSpec] = [:]
        func add(_ m: String, _ s: CPUSpec) { d[m.uppercased()] = s }

        // MARK: Ivy Bridge 移动版（HD Graphics 4000，22nm）
        // 注："5" 后缀型号（3615QM/3635QM）为 Apple 定制 BGA 焊封装；其余 QM 为 PC 笔记本插槽（rPGA988B）
        let ivyQM: [(String, Double, Double, Double, String)] = [
            // 型号, 睿频, 核显最大, TDP, 插槽
            ("i7-3610QM", 3300, 1100, 45, "G3 (rPGA988B)"),
            ("i7-3612QM", 3100, 1100, 35, "G3 (rPGA988B)"),
            ("i7-3615QM", 3300, 1200, 45, "FCBGA1224"),
            ("i7-3630QM", 3400, 1150, 45, "G3 (rPGA988B)"),
            ("i7-3632QM", 3200, 1150, 35, "G3 (rPGA988B)"),
            ("i7-3635QM", 3400, 1200, 45, "FCBGA1224"),
            ("i7-3720QM", 3600, 1250, 45, "G3 (rPGA988B)"),
            ("i7-3740QM", 3700, 1300, 45, "G3 (rPGA988B)"),
            ("i7-3820QM", 3700, 1250, 45, "G3 (rPGA988B)"),
            ("i7-3840QM", 3800, 1300, 45, "G3 (rPGA988B)"),
        ]
        for (m, turbo, igpu, tdp, socket) in ivyQM {
            add(m, CPUSpec(turboMHz: turbo, igpuName: "Intel HD Graphics 4000", igpuBaseMHz: 650,
                           igpuMaxMHz: igpu, tdpW: tdp, socket: socket, codename: "Ivy Bridge",
                           maxTempC: 105, process: "22nm"))
        }
        // Ivy Bridge XM 旗舰（55W）
        for (m, turbo, igpu) in [("i7-3920XM", 3800.0, 1300.0), ("i7-3940XM", 3900.0, 1350.0)] {
            add(m, CPUSpec(turboMHz: turbo, igpuName: "Intel HD Graphics 4000", igpuBaseMHz: 650,
                           igpuMaxMHz: igpu, tdpW: 55, socket: "G3 (rPGA988B)", codename: "Ivy Bridge",
                           maxTempC: 105, process: "22nm"))
        }
        // Ivy Bridge M 双核（35W）
        for (m, turbo, igpu) in [("i7-3520M", 3600.0, 1200.0), ("i7-3540M", 3700.0, 1300.0),
                                 ("i5-3210M", 3100.0, 1100.0), ("i5-3360M", 3500.0, 1200.0)] {
            add(m, CPUSpec(turboMHz: turbo, igpuName: "Intel HD Graphics 4000", igpuBaseMHz: 650,
                           igpuMaxMHz: igpu, tdpW: 35, socket: "G2 (rPGA988B)", codename: "Ivy Bridge",
                           maxTempC: 105, process: "22nm"))
        }

        // MARK: Haswell 移动版（HD Graphics 4600，22nm）
        let haswellMQ: [(String, Double, Double, Double)] = [
            // 型号, 睿频, 核显最大, TDP
            ("i7-4700MQ", 3400, 1150, 47),
            ("i7-4702MQ", 3200, 1150, 37),
            ("i7-4710MQ", 3500, 1150, 47),
            ("i7-4712MQ", 3300, 1150, 37),
            ("i7-4800MQ", 3700, 1300, 47),
            ("i7-4810MQ", 3800, 1300, 47),
            ("i7-4900MQ", 3800, 1300, 47),
            ("i7-4910MQ", 3900, 1300, 47),
        ]
        for (m, turbo, igpu, tdp) in haswellMQ {
            // MQ 为插槽式（FCPGA946）
            add(m, CPUSpec(turboMHz: turbo, igpuName: "Intel HD Graphics 4600", igpuBaseMHz: 400,
                           igpuMaxMHz: igpu, tdpW: tdp, socket: "G3 (FCPGA946)", codename: "Haswell",
                           maxTempC: 100, process: "22nm"))
        }
        let haswellHQ: [(String, Double, Double, Double)] = [
            ("i7-4710HQ", 3500, 1200, 47),
            ("i7-4720HQ", 3600, 1200, 47),
            ("i7-4850HQ", 3500, 1200, 47),
            ("i7-4860HQ", 3600, 1200, 47),
            ("i7-4870HQ", 3700, 1300, 47),
            ("i7-4880HQ", 3700, 1300, 47),
            ("i7-4950HQ", 3600, 1300, 47),
            ("i7-4960HQ", 3800, 1300, 47),
            ("i7-4980HQ", 4000, 1300, 47),
        ]
        for (m, turbo, igpu, tdp) in haswellHQ {
            add(m, CPUSpec(turboMHz: turbo, igpuName: "Intel HD Graphics 4600", igpuBaseMHz: 400,
                           igpuMaxMHz: igpu, tdpW: tdp, socket: "BGA1364", codename: "Haswell",
                           maxTempC: 100, process: "22nm"))
        }
        for (m, turbo, igpu) in [("i7-4930MX", 3900.0, 1350.0), ("i7-4940MX", 4000.0, 1350.0)] {
            add(m, CPUSpec(turboMHz: turbo, igpuName: "Intel HD Graphics 4600", igpuBaseMHz: 400,
                           igpuMaxMHz: igpu, tdpW: 57, socket: "G3 (rPGA988B)", codename: "Haswell",
                           maxTempC: 100, process: "22nm"))
        }
        return d
    }()
}

// MARK: - CPU 静态信息（sysctl，免授权，启动时一次性读取）

/// CPU 不随运行变化的参数：频率、核数、缓存、虚拟化、封装类型 + 官方规格
struct CPUStaticInfo {
    var brand: String = ""            // machdep.cpu.brand_string
    var modelNumber: String? = nil    // 提取的型号（i7-3615QM）
    var spec: CPUSpec? = nil          // 官方规格（睿频/核显最大频率/TDP/插槽）
    var baseFreqMHz: Double = 0       // hw.cpufrequency
    var maxFreqMHz: Double = 0        // hw.cpufrequency_max（系统上报的最大值）
    var physicalCores: Int = 0        // hw.physicalcpu
    var logicalCpus: Int = 0          // hw.logicalcpu
    var packages: Int = 1             // hw.packages
    var l1iBytes: UInt64 = 0          // hw.l1icachesize
    var l1dBytes: UInt64 = 0          // hw.l1dcachesize
    var l2Bytes: UInt64 = 0           // hw.l2cachesize
    var l3Bytes: UInt64 = 0           // hw.l3cachesize
    var virtualization: Bool = false  // machdep.cpu.features 含 VMX
    var packageType: String = "BGA（焊接）"
    var features: String = ""         // machdep.cpu.features
    var leaf7: String = ""            // machdep.cpu.leaf7_features

    /// 有效睿频：优先官方规格，否则系统上报最大值（仅当大于基础频率）
    var turboMHz: Double? { spec?.turboMHz ?? (maxFreqMHz > baseFreqMHz ? maxFreqMHz : nil) }
    /// 核显最大动态频率（官方规格）
    var igpuMaxMHz: Double? { spec?.igpuMaxMHz }

    /// 指令集摘要："SSE4.2 · AVX · AVX2 · AES-NI"
    var instructionSets: String {
        let f = features.uppercased()
        let l7 = leaf7.uppercased()
        var parts: [String] = []
        if f.contains("SSE4_2") || f.contains("SSE4.2") { parts.append("SSE4.2") }
        if f.contains("AVX") { parts.append("AVX") }
        if l7.contains("AVX2") { parts.append("AVX2") }
        if l7.contains("AVX512") { parts.append("AVX-512") }
        if f.contains("AES") { parts.append("AES-NI") }
        if virtualization { parts.append("VT-x") }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    /// "L1 64KB · L2 256KB · L3 6MB"
    var cacheText: String {
        var parts: [String] = []
        let l1 = l1iBytes + l1dBytes
        if l1 > 0 { parts.append("L1 \(Format.bytes(l1))") }
        if l2Bytes > 0 { parts.append("L2 \(Format.bytes(l2Bytes))") }
        if l3Bytes > 0 { parts.append("L3 \(Format.bytes(l3Bytes))") }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}

enum CPUInfo {

    static let shared: CPUStaticInfo = {
        let brand = sysctlString("machdep.cpu.brand_string")
        let model = CPUSpecDB.modelNumber(from: brand)
        let features = sysctlString("machdep.cpu.features")
        let leaf7 = sysctlString("machdep.cpu.leaf7_features")
        return CPUStaticInfo(
            brand: brand,
            modelNumber: model,
            spec: model.flatMap { CPUSpecDB.spec(forModel: $0) },
            baseFreqMHz: Double(sysctlUInt64("hw.cpufrequency")) / 1_000_000,
            maxFreqMHz: Double(sysctlUInt64("hw.cpufrequency_max")) / 1_000_000,
            physicalCores: Int(sysctlInt("hw.physicalcpu")),
            logicalCpus: Int(sysctlInt("hw.logicalcpu")),
            packages: max(1, Int(sysctlInt("hw.packages"))),
            l1iBytes: sysctlUInt64("hw.l1icachesize"),
            l1dBytes: sysctlUInt64("hw.l1dcachesize"),
            l2Bytes: sysctlUInt64("hw.l2cachesize"),
            l3Bytes: sysctlUInt64("hw.l3cachesize"),
            virtualization: features.uppercased().contains("VMX") || leaf7.uppercased().contains("VMX"),
            packageType: packageType(brand: brand, model: sysctlString("hw.model")),
            features: features,
            leaf7: leaf7
        )
    }()

    /// CPU 封装接口：优先官方规格库（区分插槽/焊接），否则按机型推断（MacBook 全系 BGA 焊接）
    private static func packageType(brand: String, model: String) -> String {
        if let m = CPUSpecDB.modelNumber(from: brand), let s = CPUSpecDB.spec(forModel: m), let socket = s.socket {
            if socket.contains("rPGA") || socket.contains("PGA") || socket.contains("LGA") {
                return "\(socket)（插槽）"
            }
            return "\(socket)（焊接）"
        }
        let m = model.lowercased()
        if m.contains("macbook") { return "BGA（焊接）" }
        if m.contains("macpro") || m.contains("mac pro") { return "LGA（插槽）" }
        return "BGA（焊接）"
    }

    // MARK: - sysctl 读取

    static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static func sysctlInt(_ name: String) -> Int {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname(name, &v, &size, nil, 0) == 0 { return Int(v) }
        return 0
    }

    static func sysctlUInt64(_ name: String) -> UInt64 {
        var v: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname(name, &v, &size, nil, 0) == 0, size == MemoryLayout<UInt64>.size { return v }
        return 0
    }
}

extension String {
    /// 简易正则首个匹配（供品牌串提取型号用）
    func firstMatch(of pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)),
              m.range.location != NSNotFound else { return nil }
        return ns.substring(with: m.range)
    }
}

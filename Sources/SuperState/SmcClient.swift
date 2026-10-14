import Foundation
import IOKit

// MARK: - 免授权 SMC 客户端（新版协议）

/// macOS（含 VirtualSMC / AppleSMC）新版 SMC 用户协议：
/// - 固定结构 80 字节，主 external method selector = 2
/// - 子功能号写在 offset 42：9=GetKeyInfo, 5=ReadKey, 8=GetKeyFromIndex
/// - 字段：key@0(UInt32, 主机字节序)、dataSize@28、dataType@32、result@40、data@48
/// 该通道**无需管理员权限**即可读取温度与风扇。
final class SmcClient {
    static let shared: SmcClient? = SmcClient()

    private static let structSize = 80
    private static let mainSelector: UInt32 = 2
    private static let offKey = 0
    private static let offDataSize = 28
    private static let offDataType = 32
    private static let offResult = 40
    private static let offCommand = 42
    private static let offData = 48

    private var conn: io_connect_t = 0

    private init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        IOObjectRelease(service)
        guard kr == KERN_SUCCESS else { return nil }
    }

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    // MARK: 原始调用

    @discardableResult
    private func call(command: UInt8, key: UInt32, dataSize: UInt8 = 0) -> [UInt8]? {
        var input = [UInt8](repeating: 0, count: Self.structSize)
        input[Self.offKey]     = UInt8(key & 0xff)
        input[Self.offKey + 1] = UInt8((key >> 8) & 0xff)
        input[Self.offKey + 2] = UInt8((key >> 16) & 0xff)
        input[Self.offKey + 3] = UInt8((key >> 24) & 0xff)
        input[Self.offDataSize] = dataSize
        input[Self.offCommand] = command

        var outSize = Self.structSize
        var output = [UInt8](repeating: 0, count: Self.structSize)
        let kr = IOConnectCallStructMethod(conn, Self.mainSelector,
                                           &input, Self.structSize,
                                           &output, &outSize)
        guard kr == KERN_SUCCESS, output[Self.offResult] == 0 else { return nil }
        return output
    }

    // MARK: 对外读取

    /// 读取原始键：返回 (类型, 数据)
    func readRaw(_ name: String) -> (type: String, data: [UInt8])? {
        let key = Self.fourCC(name)
        guard let info = call(command: 9, key: key),
              let value = call(command: 5, key: key, dataSize: info[Self.offDataSize]) else {
            return nil
        }
        let tOff = Self.offDataType
        var typeU = UInt32(info[tOff])
        typeU |= UInt32(info[tOff + 1]) << 8
        typeU |= UInt32(info[tOff + 2]) << 16
        typeU |= UInt32(info[tOff + 3]) << 24
        let size = Int(info[Self.offDataSize])
        let start = Self.offData
        // 防御：GPU 电源状态切换（如独显断电）时 SMC 可能返回异常 dataSize，
        // 越界切片会触发 Swift 陷阱直接闪退，必须先校验范围
        guard start <= value.count, size >= 0, start + size <= value.count else { return nil }
        let data = Array(value[start..<(start + size)])
        return (Self.typeName(typeU), data)
    }

    /// 读取温度（°C），支持 sp78 / sp4b / flt
    func readTemp(_ name: String) -> Double? {
        guard let r = readRaw(name) else { return nil }
        guard let t = Self.tempValue(type: r.type, data: r.data) else { return nil }
        // 合理性过滤：独显断电 / 传感器无效时 SMC 会返回哨兵值（如 0xFFFF、0x8000），
        // 真实硬件温度不会低于 -20°C 或高于 150°C，超出范围按「无数据」处理
        guard t >= -20, t <= 150 else { return nil }
        return t
    }

    /// 读取风扇转速（rpm），fpe2 = UInt16 BE / 4
    func readFanRpm(_ name: String) -> Double? {
        guard let r = readRaw(name), r.data.count >= 2 else { return nil }
        let raw = UInt16(r.data[0]) << 8 | UInt16(r.data[1])
        if r.type == "fpe2" { return Double(raw) / 4.0 }
        return Double(raw)
    }

    /// 独显功耗上限（SMC PG0C，sp78 定点，单位 W）。
    /// 注意：这是 SMC 提供的**功率限制**（与 powermetrics 的 "GPU Plimit" 一致）。
    func readGPUPowerLimitW() -> Double? {
        readPowerW("PG0C")
    }

    /// 独显实时功耗（SMC PG0R，GPU 导轨功率，单位 W）——免授权。
    /// 实测验证：PG0R ≈ 12.5V × IG0R（导轨电流），且随 GPU 负载动态变化
    /// （GT 650M 实测空载 17~24W、满载 27.6W）。
    func readGPURailPowerW() -> Double? {
        readPowerW("PG0R")
    }

    /// CPU 封装核心功率（SMC PCPC，单位 W）——免授权实时
    func readCPUCorePowerW() -> Double? {
        readPowerW("PCPC")
    }

    /// CPU 封装总功率（SMC PCPT，单位 W）——免授权实时。
    /// 实测与 powermetrics 的整机功耗 (CPUs+GT+SA) 几乎一致（偏差 < 0.6W）。
    func readPackageTotalPowerW() -> Double? {
        readPowerW("PCPT")
    }

    /// 核显功率（SMC PCPG，单位 W）——免授权；独显模式下核显断电读 0
    func readIGPUPowerW() -> Double? {
        readPowerW("PCPG")
    }

    /// 通用功率键读取（sp78/sp4b 等定点，合理范围 0~500W）
    private func readPowerW(_ key: String) -> Double? {
        guard let r = readRaw(key) else { return nil }
        guard let v = Self.tempValue(type: r.type, data: r.data) else { return nil }
        guard v >= 0, v < 500 else { return nil }
        return v
    }

    // MARK: 写入（风扇控制）

    /// 写 SMC 键（command 6 = WriteKey）。仅用于风扇控制，写前必须确认键存在。
    /// 注意：本机实测（macOS 26 + AppleSMC 3.1.9）非特权进程的 WriteKey 一律返回
    /// kIOReturnNotPrivileged (0xE00002C1)，调用方需按 kr 决定是否走管理员通道。
    @discardableResult
    func writeRaw(_ name: String, data: [UInt8]) -> Bool {
        writeRawStatus(name, data: data).ok
    }

    /// 同 writeRaw，但返回原始 IOReturn，供调用方区分「权限不足」与其他失败
    func writeRawStatus(_ name: String, data: [UInt8]) -> (ok: Bool, kr: kern_return_t) {
        let key = Self.fourCC(name)
        guard let info = call(command: 9, key: key) else { return (false, kIOReturnNotFound) }
        let size = Int(info[Self.offDataSize])
        guard size > 0, data.count == size else { return (false, kIOReturnBadArgument) }
        var input = [UInt8](repeating: 0, count: Self.structSize)
        input[Self.offKey]     = UInt8(key & 0xff)
        input[Self.offKey + 1] = UInt8((key >> 8) & 0xff)
        input[Self.offKey + 2] = UInt8((key >> 16) & 0xff)
        input[Self.offKey + 3] = UInt8((key >> 24) & 0xff)
        input[Self.offDataSize] = UInt8(size)
        input[Self.offCommand] = 6   // WriteKey
        for (i, b) in data.enumerated() where Self.offData + i < input.count {
            input[Self.offData + i] = b
        }
        var outSize = Self.structSize
        var output = [UInt8](repeating: 0, count: Self.structSize)
        let kr = IOConnectCallStructMethod(conn, Self.mainSelector,
                                           &input, Self.structSize,
                                           &output, &outSize)
        return (kr == KERN_SUCCESS && output[Self.offResult] == 0, kr)
    }

    // MARK: 键枚举（全量传感器发现）

    /// 枚举 SMC 全部键名（command 8 = GetKeyFromIndex，直到返回错误为止）
    /// 协议要点（本机实测）：索引写在 data32@44，输出 key 在 @0 且为反序字节
    func enumerateKeys() -> [String] {
        var keys: [String] = []
        var idx: UInt32 = 0
        while idx < 1024 {
            var input = [UInt8](repeating: 0, count: Self.structSize)
            input[Self.offCommand] = 8
            input[44] = UInt8(idx & 0xff)
            input[45] = UInt8((idx >> 8) & 0xff)
            input[46] = UInt8((idx >> 16) & 0xff)
            input[47] = UInt8((idx >> 24) & 0xff)
            var outSize = Self.structSize
            var output = [UInt8](repeating: 0, count: Self.structSize)
            let kr = IOConnectCallStructMethod(conn, Self.mainSelector,
                                               &input, Self.structSize,
                                               &output, &outSize)
            guard kr == KERN_SUCCESS, output[Self.offResult] == 0 else { break }
            // key@0，字节序与 FourCC 相反（实测 output=0x59,0x45,0x4B,0x23 → "#KEY"）
            let k = UInt32(output[3]) << 24 |
                    UInt32(output[2]) << 16 |
                    UInt32(output[1]) << 8 |
                    UInt32(output[0])
            let name = Self.typeName(k)
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            keys.append(name)
            idx += 1
        }
        return keys
    }

    // MARK: 风扇控制

    /// 风扇数量（SMC FNum）
    func fanCount() -> Int {
        guard let r = readRaw("FNum"), r.data.count >= 1 else { return 2 }
        return Int(r.data[0])
    }

    /// 风扇转速上限 / 下限（F0Mx / F0Mn）
    func fanMaxRpm(_ i: Int) -> Double? {
        guard let r = readRaw("F\(i)Mx"), r.data.count >= 2 else { return nil }
        return Double(UInt16(r.data[0]) << 8 | UInt16(r.data[1])) / 4.0
    }
    func fanMinRpm(_ i: Int) -> Double? {
        guard let r = readRaw("F\(i)Mn"), r.data.count >= 2 else { return nil }
        return Double(UInt16(r.data[0]) << 8 | UInt16(r.data[1])) / 4.0
    }

    /// 风扇模式：0=系统自动，1=手动。
    /// 注意：FS! 是多字节类型（本机实测 ui16/2B 大端），必须读**最后一个字节**；
    /// 读首字节在 ui16/flag 机型上会永远显示"自动"。
    var fanMode: Int {
        guard let r = readRaw("FS! "), !r.data.isEmpty else { return 0 }
        return Int(r.data[r.data.count - 1])
    }

    /// 切换风扇模式（false=系统自动，true=手动）。
    /// FS! 尺寸随机型不同（本机实测 ui16/2B；其他机型有 flag/4B、ui8/1B），
    /// 先取 GetKeyInfo 真实 size，按大端在末字节写 1/0。
    /// 曾因固定只写 1 字节、与 ui16 尺寸不匹配被 SMC 拒绝，导致手动模式从未生效。
    @discardableResult
    func setFanMode(manual: Bool) -> Bool {
        setFanModeStatus(manual: manual).ok
    }

    /// 同 setFanMode，返回原始 IOReturn（区分权限不足与其他失败）
    func setFanModeStatus(manual: Bool) -> (ok: Bool, kr: kern_return_t) {
        let key = Self.fourCC("FS! ")
        guard let info = call(command: 9, key: key) else { return (false, kIOReturnNotFound) }
        let size = Int(info[Self.offDataSize])
        guard size >= 1, size <= 4 else { return (false, kIOReturnBadArgument) }
        var data = [UInt8](repeating: 0, count: size)
        data[size - 1] = manual ? 1 : 0
        return writeRawStatus("FS! ", data: data)
    }

    /// 设置第 i 个风扇目标转速（手动模式生效；fpe2 编码 = rpm×4）
    @discardableResult
    func setFanTarget(_ i: Int, rpm: Double) -> Bool {
        setFanTargetStatus(i, rpm: rpm).ok
    }

    /// 同 setFanTarget，返回原始 IOReturn（区分权限不足与其他失败）
    func setFanTargetStatus(_ i: Int, rpm: Double) -> (ok: Bool, kr: kern_return_t) {
        writeFpe2Status("F\(i)Tg", value: rpm)
    }

    private func writeFpe2Status(_ name: String, value: Double) -> (ok: Bool, kr: kern_return_t) {
        let scaled = max(0, min(16383, value))
        let v = UInt16(scaled * 4)
        return writeRawStatus(name, data: [UInt8(v >> 8), UInt8(v & 0xff)])
    }

    // MARK: 解析工具

    static func fourCC(_ s: String) -> UInt32 {
        var v: UInt32 = 0
        for b in s.utf8 { v = (v << 8) | UInt32(b) }
        return v
    }

    static func typeName(_ u: UInt32) -> String {
        var s = ""
        for sh in [24, 16, 8, 0] {
            s.append(Character(UnicodeScalar((u >> sh) & 0xff)!))
        }
        return s
    }

    static func tempValue(type: String, data: [UInt8]) -> Double? {
        if type == "flt ", data.count >= 4 {
            var f: Float = 0
            data.withUnsafeBytes { _ = memcpy(&f, $0.baseAddress, 4) }
            return Double(f)
        }
        if type.contains("sp"), data.count >= 2 {
            // sp78 / sp4b 是有符号 16 位定点温度，必须按「位模式」转换。
            // 注意：不能写 Int16(UInt16(...))——值 >= 0x8000 时会触发
            // "Not enough bits to represent the passed value" 溢出陷阱（SIGILL 闪退）。
            // 独显断电后 TG1D 等键会返回 0xFFFF 之类的无效值，曾导致 100% 崩溃。
            let raw = Int16(bitPattern: UInt16(data[0]) << 8 | UInt16(data[1]))
            switch type {
            case "sp78": return Double(raw) / 256.0
            case "sp4b": return Double(raw) / 16.0
            default: return Double(raw) / 256.0
            }
        }
        if type == "ui8 ", data.count >= 1 {
            return Double(data[0])
        }
        return nil
    }
}

// MARK: - 传感器键映射（集中管理，便于扩展）

enum SensorMap {
    /// CPU 整体/封装温度
    static let cpuMain = "TC0P"
    /// CPU 各核心/模块温度（TC1C~TC4C 为真实单核心传感器，与 iFan Core 1-4 一致）
    static let cpuCores = ["TC1C", "TC2C", "TC3C", "TC4C"]
    /// 核显温度
    static let gpuIntegrated = "TG0P"
    /// 独显温度（候选，按序尝试）
    static let gpuDiscrete = ["TG1D", "TG0D", "TG1P"]
    /// 风扇实际转速
    static let fans = ["F0Ac", "F1Ac"]
    /// 电池温度
    static let battery = "TB0T"
}

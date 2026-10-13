import Foundation

/// 平台身份识别：分辨「原生 Mac / OCLP / OpenCore(黑苹果)」，并推断出厂(原生)机型
enum PlatformIdentity {

    enum Environment: String {
        case native = "原生 Mac"
        case oclp = "OCLP（OpenCore Legacy Patcher）"
        case opencore = "OpenCore（黑苹果）"
    }

    /// SMBIOS 当前报告机型（可能被 OCLP / OpenCore 改写）
    static var reportedModel: String { DashboardInfo.sysctlString("hw.model") }
    static var cpuBrand: String { DashboardInfo.sysctlString("machdep.cpu.brand_string") }

    static var environment: Environment {
        if hasOCLPDaemon { return .oclp }
        if hasLilu { return .opencore }
        return .native
    }

    static var isPatched: Bool { environment != .native }

    // MARK: - OCLP 检测（com.dortania.opencore-legacy-patcher.*）

    private static var hasOCLPDaemon: Bool {
        let dirs = ["/Library/LaunchDaemons", "/Library/LaunchAgents"]
        for d in dirs {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []
            if names.contains(where: {
                let n = $0.lowercased()
                return n.contains("opencore-legacy-patcher") || n.contains("dortania")
            }) {
                return true
            }
        }
        return false
    }

    // MARK: - Lilu / VirtualSMC 检测（OpenCore 生态，内核加载）

    private static var hasLilu: Bool {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/sbin/kextstat")
        t.arguments = ["-l"]
        let pipe = Pipe()
        t.standardOutput = pipe
        t.standardError = Pipe()
        do { try t.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        t.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains("as.vit9696.Lilu")
            || text.contains("as.vit9696.VirtualSMC")
    }

    // MARK: - 出厂(原生)机型推断（按 CPU）

    /// 根据 CPU 型号推断出厂机型；识别不到返回 nil
    static var nativeModel: String? {
        // Ivy Bridge（2012）四核 + 独显 = 15" Retina；双核 = 13"
        let ivyQuad = ["3610QM","3615QM","3720QM","3740QM","3820QM","3840QM","3920XM"]
        let ivyDual = ["3520M","3210M","3230M","3360M","3380M"]
        if ivyQuad.contains(where: { cpuBrand.contains($0) }) { return "MacBookPro10,1" }
        if ivyDual.contains(where: { cpuBrand.contains($0) }) { return "MacBookPro10,2" }

        // Haswell（2013/2014）
        let haswellQuad = ["4770HQ","4870HQ","4960HQ","4980HQ","4700HQ","4800HQ","4900HQ","4960HQ"]
        let haswellDual = ["4258U","4278U","4288U","4558U","4578U"]
        if haswellQuad.contains(where: { cpuBrand.contains($0) }) { return "MacBookPro11,2 / 11,3" }
        if haswellDual.contains(where: { cpuBrand.contains($0) }) { return "MacBookPro11,1" }

        // Skylake/Kaby Lake 系（2016-2019 15"/13"）
        let skylake15 = ["6700HQ","6820HQ","6920HQ","7700HQ","7820HQ","7920HQ"]
        let skylake13 = ["6267U","6287U","6567U","7360U","7567U","7660U","8559U","8259U"]
        if skylake15.contains(where: { cpuBrand.contains($0) }) { return "MacBookPro13,3 / 14,3 / 15,1" }
        if skylake13.contains(where: { cpuBrand.contains($0) }) { return "MacBookPro13,2 / 14,2 / 15,2" }

        return nil
    }
}

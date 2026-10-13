import Foundation

// MARK: - 全量温度传感器（对齐 iFan：SMC 所有 T 开头温度键）

struct SensorTemp: Identifiable {
    let key: String
    let label: String
    let tempC: Double
    var id: String { key }
}

/// SMC 温度传感器发现与读取（免授权）
enum TempSensors {

    /// 已知键的中文名（对齐 iFan 命名习惯；未知键显示原名）
    static let displayNames: [String: String] = [
        // CPU
        "TC0P": "CPU 封装（Package）",
        "TC1C": "CPU 核心 1", "TC2C": "CPU 核心 2", "TC3C": "CPU 核心 3", "TC4C": "CPU 核心 4",
        "TC0E": "CPU Die", "TC0F": "CPU 风扇区", "TC0H": "CPU 散热器", "TC0C": "CPU 核心（聚合）",
        "TC1C ": "CPU 核心（传感器）", "TCGC": "CPU GT 聚合", "TCXC": "CPU（聚合）", "TCTD": "CPU 二极管",
        // GPU
        "TG0P": "Intel 核显", "TG0D": "Intel 核显 Die",
        "TG1D": "独显（NVIDIA）", "TG1F": "独显（过滤）", "TG1d": "独显（二极管）", "TG0T": "独显（NVIDIA）",
        // 掌托 / 环境
        "TP0P": "掌托（Palm）", "TPCD": "掌托（过滤）", "TP0D": "掌托二极管",
        "Ta0P": "环境（进风）", "TaSP": "环境（过滤）", "TA0P": "环境（Airflow）", "TA0S": "环境（filtered）",
        "Ts0P": "接近传感器", "Ts0S": "接近传感器 2", "Ts1S": "接近传感器 3",
        // 主板 / 内存
        "TM0P": "主板", "Tm0P": "主板（Proximity）", "TM0S": "内存槽 1", "TMBS": "内存（Bus）",
        "TCMF": "内存", "TN0D": "北桥", "TN0P": "北桥（PECI）",
        // 散热器
        "Th1H": "散热器 1", "Th2H": "散热器 2",
        // 电池
        "TB0T": "电池", "TB1T": "电池 2", "TB2T": "电池 3",
        // 硬盘 / SSD
        "TH0A": "硬盘 1", "TH0B": "硬盘 2", "TH0a": "硬盘 1（二极管）", "TH0b": "硬盘 2（二极管）",
        "TH0x": "硬盘（聚合）", "TH0V": "硬盘（电压区）", "TH0P": "硬盘（HDD）",
        // 其他
        "TW0P": "Wi-Fi（Airport）",
        "TV0P": "电压区", "TV0D": "电源二极管",
        "TI0P": "中断（CPU）",
    ]

    /// 传感器分组（功能页按类别展示）
    static func category(of key: String) -> String {
        switch key.prefix(2) {
        case "TC": return "CPU"
        case "TG": return "GPU"
        case "TB": return "电池"
        case "TH": return "硬盘 / SSD"
        case "TM", "TN": return "主板 / 内存"
        case "TP": return "掌托"
        case "Ta", "TA": return "环境"
        case "Ts": return "接近传感器"
        case "Th": return "散热器"
        case "TW": return "网络"
        case "TV": return "电源"
        default: return "其他"
        }
    }

    /// 温度类型（sp78 / sp4b 定点、flt 浮点）
    static func isTempType(_ type: String) -> Bool {
        type == "flt " || type == "sp78" || type == "sp4b" || type == "fp1f" || type == "fp2e" || type == "fpe2"
    }

    /// 发现全部温度传感器键（T 开头 + 温度类型），启动时执行一次
    static func discoverKeys() -> [String] {
        guard let smc = SmcClient.shared else { return [] }
        return smc.enumerateKeys().filter { key in
            key.hasPrefix("T") && key.count == 4 &&
            (key != "TCSA" && key != "TVRU")
        }.filter { key in
            guard let r = smc.readRaw(key) else { return false }
            return isTempType(r.type)
        }
    }

    static func label(for key: String) -> String {
        displayNames[key] ?? key
    }

    /// 读取所有已发现传感器的当前值（无效/断电传感器自动跳过）
    static func readAll(keys: [String]) -> [SensorTemp] {
        guard let smc = SmcClient.shared else { return [] }
        return keys.compactMap { key in
            guard let t = smc.readTemp(key) else { return nil }
            return SensorTemp(key: key, label: label(for: key), tempC: t)
        }
    }
}

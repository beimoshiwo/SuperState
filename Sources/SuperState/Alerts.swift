import Foundation
import UserNotifications

/// 阈值告警：CPU / 内存 / GPU 占用率 / GPU 温度超限时系统通知
final class Alerts {

    static let shared = Alerts()

    // 阈值（UserDefaults，可在面板中调节）
    var cpuThreshold: Double {
        get { UserDefaults.standard.object(forKey: "alert.cpu") as? Double ?? 80 }
        set { UserDefaults.standard.set(newValue, forKey: "alert.cpu") }
    }
    var memThreshold: Double {
        get { UserDefaults.standard.object(forKey: "alert.mem") as? Double ?? 85 }
        set { UserDefaults.standard.set(newValue, forKey: "alert.mem") }
    }
    var gpuUtilThreshold: Double {
        get { UserDefaults.standard.object(forKey: "alert.gpuUtil") as? Double ?? 90 }
        set { UserDefaults.standard.set(newValue, forKey: "alert.gpuUtil") }
    }
    var gpuTempThreshold: Double {
        get { UserDefaults.standard.object(forKey: "alert.gpuTemp") as? Double ?? 85 }
        set { UserDefaults.standard.set(newValue, forKey: "alert.gpuTemp") }
    }
    var gpuPowerThreshold: Double {
        get { UserDefaults.standard.object(forKey: "alert.gpuPower") as? Double ?? 20 }
        set { UserDefaults.standard.set(newValue, forKey: "alert.gpuPower") }
    }
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "alert.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "alert.enabled") }
    }

    private var lastFired: [String: Date] = [:]
    private let cooldown: TimeInterval = 60

    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 立即发送一条通知（安全关键事件用，不受启用开关与冷却限制）
    func postNow(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "superstate.now.\(Date().timeIntervalSince1970)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func check(_ s: SystemSnapshot) {
        guard enabled else { return }
        var items: [(key: String, title: String, body: String)] = []

        if s.cpuUsage >= cpuThreshold {
            items.append(("cpu", "CPU 占用过高", String(format: "当前 CPU 占用 %.1f%%（阈值 %.0f%%）", s.cpuUsage, cpuThreshold)))
        }
        if s.memPressurePercent >= memThreshold {
            items.append(("mem", "内存压力过高", String(format: "当前内存压力 %.1f%%（阈值 %.0f%%）", s.memPressurePercent, memThreshold)))
        }
        for gpu in s.gpus where gpu.available {
            if gpu.utilization >= gpuUtilThreshold {
                items.append(("gpuU-\(gpu.name)", "\(gpu.name) 占用过高",
                              String(format: "当前占用 %.1f%%（阈值 %.0f%%）", gpu.utilization, gpuUtilThreshold)))
            }
            if let t = gpu.temperatureC, t >= gpuTempThreshold {
                items.append(("gpuT-\(gpu.name)", "\(gpu.name) 温度过高",
                              String(format: "当前温度 %.1f°C（阈值 %.0f°C）—— 高温易触发 GPU 复位/系统卡死，建议降低负载", t, gpuTempThreshold)))
            }
            if !gpu.isIntegrated, let p = gpu.powerWatts, p >= gpuPowerThreshold {
                items.append(("gpuP-\(gpu.name)", "\(gpu.name) 功耗过高",
                              String(format: "当前 %.1fW（阈值 %.0fW）—— 独显高负载可能触发复位/关机保护，建议降低负载", p, gpuPowerThreshold)))
            }
        }

        for item in items {
            fire(key: item.key, title: item.title, body: item.body)
        }
    }

    private func fire(key: String, title: String, body: String) {
        let now = Date()
        if let last = lastFired[key], now.timeIntervalSince(last) < cooldown { return }
        lastFired[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "superstate.\(key).\(now.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

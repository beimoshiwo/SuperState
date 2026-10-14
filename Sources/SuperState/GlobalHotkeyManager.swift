import AppKit
import Carbon

// MARK: - 系统级全局热键（Carbon RegisterEventHotKey）
//
// 背景：菜单栏 App 的快捷键原本是状态项菜单（右键点出）的 keyEquivalent，
//       只有把菜单点出来按才生效——不符合"随时一按就触发"的预期。
// 方案：用 Carbon 的 RegisterEventHotKey 注册**系统级全局热键**，
//       App 失焦 / 未激活 / 菜单没点开时，按下组合键也能触发对应动作。
//       RegisterEventHotKey 不需要"辅助功能/输入监控"授权（比 NSEvent 全局 monitor 更省心）。
//
// 默认组合（可在下方 hotKeyDefs 调整）：
//   ⌘M      打开主界面
//   ⌘⌥P     状态面板（显示/隐藏）
//   ⌘⌥F     网速悬浮窗（显示/隐藏）

final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var registered: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private let signature = OSType(0x5353_4B45)   // "SSKE"

    private init() {}

    /// 热键定义表：id / 虚拟键码 / 修饰键
    private var hotKeyDefs: [(id: UInt32, key: UInt32, mods: UInt32)] {
        [
            (1, UInt32(kVK_ANSI_M), UInt32(cmdKey)),                 // ⌘M   打开主界面
            (2, UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey)),     // ⌘⌥P  状态面板
            (3, UInt32(kVK_ANSI_F), UInt32(cmdKey | optionKey)),     // ⌘⌥F  网速悬浮窗
        ]
    }

    func register() {
        guard registered.isEmpty else { return }

        // 安装 Carbon 热键按下事件处理器
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         globalHotKeyCallback,
                                         1, &spec, nil, &handlerRef)
        if status != noErr {
            NSLog("SuperState: 全局热键事件处理器安装失败 status=\(status)")
        }

        for d in hotKeyDefs {
            var ref: EventHotKeyRef?
            let s = RegisterEventHotKey(d.key, d.mods,
                                        EventHotKeyID(signature: signature, id: d.id),
                                        GetApplicationEventTarget(), 0, &ref)
            if s == noErr {
                registered.append(ref)
                NSLog("SuperState: 已注册全局热键 id=\(d.id)")
            } else {
                // 常见失败：组合键被其它 App 占用（errEHSHotKeyExists）——不致命，跳过即可
                NSLog("SuperState: 全局热键 id=\(d.id) 注册失败 status=\(s)（可能被占用）")
            }
        }
    }

    func unregister() {
        for ref in registered { if let r = ref { UnregisterEventHotKey(r) } }
        registered.removeAll()
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
    }

    /// 热键触发 → 分发到对应动作（Carbon 回调在任意线程，切回主队列执行 UI 操作）
    fileprivate func fire(_ id: UInt32) {
        DispatchQueue.main.async {
            switch id {
            case 1: MainWindowController.shared.show()
            case 2: StatusItemController.shared.togglePanelFromHotkey()
            case 3: FloatingWindowController.shared.toggle()
            default: break
            }
        }
    }
}

/// Carbon 事件处理器（必须是 C 调用约定的自由函数）
private func globalHotKeyCallback(_ nextHandler: EventHandlerCallRef?,
                                  _ event: EventRef?,
                                  _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event = event else { return noErr }
    var hkID = EventHotKeyID()
    let err = GetEventParameter(event,
                                EventParamName(kEventParamDirectObject),
                                EventParamType(typeEventHotKeyID),
                                nil,
                                MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    if err == noErr {
        GlobalHotkeyManager.shared.fire(hkID.id)
    }
    return noErr
}

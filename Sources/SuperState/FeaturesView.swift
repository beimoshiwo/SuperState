import SwiftUI

// MARK: - 功能页：风扇调节（复刻 iFan）+ 全量温度传感器

enum FanMode: String, CaseIterable {
    case system = "系统"
    case max = "最大"
    case manual = "手动"
    case custom = "自定义"
}

struct FeaturesView: View {
    @ObservedObject var monitor = Monitor.shared

    @State private var mode: FanMode = .system
    @State private var fanCount = 2
    @State private var maxRpms: [Double] = []
    @State private var minRpms: [Double] = []
    @State private var sliderPercents: [Double] = [60, 60]     // 手动模式每风扇百分比
    @State private var customPercents: [Double] = [50, 50]     // 自定义预设（持久化）
    @State private var restoreMessage: String?

    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // 模式切换（iFan 同款四段）
                sectionTitle("风扇调节", subtitle: "控制系统风扇转速；手动/自定义模式有过热风险，请谨慎设置")
                Picker("模式", selection: $mode) {
                    ForEach(FanMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { applyMode($0) }

                if mode == .manual || mode == .custom {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("当前为手动控制风扇，系统不再自动调速；退出 App 会自动恢复系统自动模式。请勿设置过低转速。")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                if let msg = restoreMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }

                // 风扇卡片（iFan 布局：名称 + 转速 + 滑杆）
                ForEach(0..<fanCount, id: \.self) { i in
                    fanCard(i)
                }

                Divider()

                // 全量温度（iFan 口径，按类别分组）
                sectionTitle("温度", subtitle: "SMC 全量传感器（免授权）· 与 iFan 同源")
                if s.sensorTemps.isEmpty {
                    Text("正在读取传感器…").font(.caption).foregroundStyle(.secondary)
                } else {
                    let grouped = Dictionary(grouping: s.sensorTemps) { TempSensors.category(of: $0.key) }
                    let order = ["CPU", "GPU", "主板 / 内存", "散热器", "硬盘 / SSD", "电池", "掌托", "环境", "接近传感器", "网络", "电源", "其他"]
                    ForEach(order.filter { grouped[$0] != nil }, id: \.self) { cat in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cat).font(.caption.bold()).foregroundStyle(.secondary)
                            VStack(spacing: 0) {
                                let list = (grouped[cat] ?? []).sorted { $0.tempC > $1.tempC }
                                ForEach(list) { st in
                                    HStack {
                                        Text(st.label).font(.callout)
                                        Spacer()
                                        Text(String(format: "%.1f°C", st.tempC))
                                            .font(.callout.monospaced())
                                            .foregroundStyle(tempColor(st.tempC))
                                    }
                                    .padding(.vertical, 3)
                                    if st.id != list.last?.id {
                                        Divider().opacity(0.4)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear(perform: loadFanInfo)
    }

    // MARK: 风扇卡片

    private func fanCard(_ i: Int) -> some View {
        let rpm = fanRpm(i)
        let maxR = i < maxRpms.count ? maxRpms[i] : 6000
        let minR = i < minRpms.count ? minRpms[i] : maxR * 0.3
        let editing = (mode == .manual || mode == .custom)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(i == 0 ? "左风扇" : "右风扇").font(.headline)
                Spacer()
                Text("\(Int(rpm)) RPM").font(.title3.bold().monospacedDigit())
                Text("/ \(Int(maxR))").font(.caption).foregroundStyle(.tertiary)
            }
            if editing {
                HStack {
                    Slider(value: binding(for: i),
                           in: max(0.3, minR / maxR)...1.0, step: 0.05)
                    Text("\(Int(binding(for: i).wrappedValue * 100))%")
                        .font(.callout.monospaced()).frame(width: 48, alignment: .trailing)
                }
            } else {
                // 只读态：显示当前转速占最大转速比例
                ProgressView(value: min(1, rpm / maxR))
                    .progressViewStyle(.linear)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func binding(for i: Int) -> Binding<Double> {
        Binding(
            get: { mode == .custom ? (i < customPercents.count ? customPercents[i] : 0.5)
                                      : (i < sliderPercents.count ? sliderPercents[i] : 0.5) },
            set: { v in
                if mode == .custom {
                    if i < customPercents.count { customPercents[i] = v } else { customPercents.append(v) }
                    UserDefaults.standard.set(customPercents, forKey: "fan.custom")
                } else {
                    if i < sliderPercents.count { sliderPercents[i] = v } else { sliderPercents.append(v) }
                }
                applySlider(i)   // 拖动即生效
            }
        )
    }

    private func fanRpm(_ i: Int) -> Double {
        if i < s.fans.count { return s.fans[i].rpm }
        return 0
    }

    // MARK: 模式应用

    private func loadFanInfo() {
        fanCount = max(2, SmcClient.shared?.fanCount() ?? 2)
        maxRpms = (0..<fanCount).map { SmcClient.shared?.fanMaxRpm($0) ?? 6000 }
        minRpms = (0..<fanCount).map { SmcClient.shared?.fanMinRpm($0) ?? 1800 }
        if let saved = UserDefaults.standard.array(forKey: "fan.custom") as? [Double], saved.count == fanCount {
            customPercents = saved
        }
        // 与当前系统风扇模式同步
        if let smc = SmcClient.shared, smc.fanMode == 1 {
            mode = .manual
            for i in 0..<fanCount {
                let target = smc.readFanRpm("F\(i)Tg") ?? 0
                if maxRpms[i] > 0 { sliderPercents[i] = min(1, target / maxRpms[i]) }
            }
        }
    }

    private func applyMode(_ m: FanMode) {
        guard let smc = SmcClient.shared else { return }
        restoreMessage = nil
        switch m {
        case .system:
            smc.setFanMode(manual: false)
        case .max:
            smc.setFanMode(manual: true)
            for i in 0..<fanCount { smc.setFanTarget(i, rpm: maxRpms[i]) }
        case .manual:
            smc.setFanMode(manual: true)
            for i in 0..<fanCount { applySlider(i) }
        case .custom:
            smc.setFanMode(manual: true)
            for i in 0..<fanCount {
                let pct = i < customPercents.count ? customPercents[i] : 0.5
                smc.setFanTarget(i, rpm: maxRpms[i] * pct)
            }
        }
    }

    private func applySlider(_ i: Int) {
        guard let smc = SmcClient.shared, i < maxRpms.count else { return }
        let pct = binding(for: i).wrappedValue
        smc.setFanMode(manual: true)
        smc.setFanTarget(i, rpm: maxRpms[i] * pct)
    }

    private func tempColor(_ t: Double) -> Color {
        if t >= 90 { return .red }
        if t >= 75 { return .orange }
        return .primary
    }

    private func sectionTitle(_ t: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.headline)
            if let sub = subtitle {
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// App 退出前恢复系统自动风扇（安全兜底）
    static func restoreAuto() {
        SmcClient.shared?.setFanMode(manual: false)
    }
}

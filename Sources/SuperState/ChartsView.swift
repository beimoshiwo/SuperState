import SwiftUI

/// 迷你折线图（Canvas 自绘，避免额外依赖）
struct Sparkline: View {
    var data: [Double]
    var color: Color = .blue
    var maxValue: Double = 100

    var body: some View {
        Canvas { ctx, size in
            guard data.count > 1, size.width > 2, size.height > 2 else { return }
            var path = Path()
            let step = size.width / CGFloat(data.count - 1)
            for (i, v) in data.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height * (1 - CGFloat(min(max(v, 0), maxValue) / maxValue))
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [color.opacity(0.25), color.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 30)
    }
}

/// 带标题与数值的迷你指标卡
struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    var data: [Double]
    var color: Color
    var maxValue: Double = 100
    /// 传入时用进度条替代曲线（活动监视器风格，如内存压力绿色条）
    var barValue: Double? = nil
    var barColor: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.system(size: 15, weight: .bold, design: .monospaced))
            }
            if let barValue {
                Bar(value: barValue, color: barColor)
                    .padding(.vertical, 9)
            } else {
                Sparkline(data: data, color: color, maxValue: maxValue)
            }
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// 内存压力配色，与活动监视器/xnu jetsam 阈值对齐：
/// 压力 <60%（可用 >40%）正常→绿；60~80%（可用 20~40%）警告→橙；≥80%（可用 ≤20%）紧急→红
func pressureColor(_ pressure: Double) -> Color {
    switch pressure {
    case ..<60: return .green
    case ..<80: return .orange
    default: return .red
    }
}

/// 进度条
struct Bar: View {
    var value: Double // 0-100
    var color: Color = .blue

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2))
                Capsule().fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 100)) / 100)
            }
        }
        .frame(height: 6)
    }
}

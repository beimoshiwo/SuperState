import SwiftUI

// MARK: - 关于页

struct AboutView: View {
    @State private var showChangelog = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }
    private var buildVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 头部：图标 + 名称 + 版本
                HStack(spacing: 16) {
                    Image(nsImage: NSImage(named: NSImage.Name("SuperState")) ?? NSImage())
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SuperState").font(.largeTitle.bold())
                        Text("比 State 更强的 macOS 系统监控").font(.subheadline).foregroundStyle(.secondary)
                        Text("版本 \(appVersion)（\(buildVersion)）")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }

                // 软件信息
                section("软件信息") {
                    infoRow("版本", "\(appVersion)（\(buildVersion)）")
                    infoRow("Bundle ID", "com.superstate.app")
                    infoRow("运行环境", HWSystemInfo.osVersion + "（\(HWSystemInfo.osBuild)）")
                    infoRow("内核", HWSystemInfo.kernelVersion)
                    infoRow("序列号", HWSystemInfo.serial)
                    infoRow("平台", PlatformIdentity.isPatched
                            ? "\(PlatformIdentity.environment.rawValue) · 出厂机型 \(PlatformIdentity.nativeModel ?? "无法确定")"
                            : PlatformIdentity.environment.rawValue)
                }

                // 功能
                section("功能") {
                    feature("双卡拆分", "核显 / 独显独立卡片：占用率、温度、频率、显存、功耗")
                    feature("免授权 SMC", "CPU/GPU 温度、双风扇转速、电池温度，无需管理员密码")
                    feature("独显实时频率", "IOAccelerator PerformanceStatistics 实时核心时钟（Hz）")
                    feature("独显实时功耗", "SMC PG0R 导轨功率免授权读取，随负载动态变化")
                    feature("硬件监控驱动", "可选 kext：免密码逐核实时频率 + 整机/核心/核显/内存 RAPL 功率")
                    feature("功率导轨", "SMC PCPT/PCPC 免授权读取英特尔整机与 CPU 核心功率")
                    feature("真实内存压力", "内核级内存压力，按等级绿/橙/红变色，与活动监视器对齐")
                    feature("CPU 详情", "每核 8 线程实时占用、缓存、睿频、虚拟化、封装、进程/线程/句柄")
                    feature("内存详情", "占用/压力切换、Swap、活跃/联动/压缩、速度 MT/s、插槽或焊接")
                    feature("历史曲线", "每指标 300 点实时折线")
                    feature("智能告警", "CPU/内存/GPU 占用/温度阈值系统通知")
                    feature("硬件参数", "CPU/内存/GPU/存储/显示/网络/电池详细规格检测")
                    feature("平台识别", "自动分辨原生 Mac / OCLP / OpenCore 并推断出厂机型")
                    feature("指令集优化", "按本机处理器（SSE4.2 / AVX）优化编译")
                }

                // 更新日志（二级页面入口）
                section("版本记录") {
                    Button {
                        showChangelog = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.blue)
                            Text("更新日志").font(.callout)
                            Spacer()
                            Text("v\(appVersion)").font(.caption).foregroundStyle(.tertiary)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // 说明
                section("说明") {
                    Text("温度、风扇、独显频率、独显功耗（导轨）、整机 / CPU 功耗均免授权；实时 CPU 频率与各域精细功率需安装硬件监控驱动（一次性授权）或用管理员模式（powermetrics）。该应用为本地开发构建（ad-hoc 签名），仅限本机使用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showChangelog) { ChangelogView() }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.monospaced()).lineLimit(1).truncationMode(.tail)
        }
    }

    private func feature(_ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(desc).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

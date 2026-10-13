import SwiftUI

// MARK: - 更新日志（关于页的二级页面）

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏
            HStack {
                Text("更新日志").font(.headline)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    changelog("1.0.13", [
                        "工具页明确标注：驱动已内置在 App 内，分享 App 即可，对方一次点击安装使用",
                    ])
                    changelog("1.0.12", [
                        "新增「功能」页：风扇调节（系统 / 最大 / 手动 / 自定义四模式，逐风扇滑杆，退出自动恢复系统控扇）",
                        "全量温度传感器（42 个，iFan 同源）：按 CPU/GPU/主板/硬盘/电池/掌托/环境分组展示",
                        "核心温度改用真实单核心传感器 TC1C~TC4C（与 iFan Core 1-4 一致）",
                    ])
                    changelog("1.0.11", [
                        "告警增强：新增 GPU 功耗阈值（默认 20W），GPU 温度默认 85°C，触发时提示降低负载以防 GPU 复位/死机",
                        "菜单栏 GPU 频率项改用型号简称（GT 650M / HD 4000）",
                        "设置新增功率单位切换：自动（<1W 毫瓦）/ 始终瓦 / 始终毫瓦",
                        "移除状态面板显示勾选项，面板模块始终全部展示",
                        "状态面板 CPU 卡片详细信息默认折叠，点击展开/收起（仪表盘不变）",
                    ])
                    changelog("1.0.10", [
                        "菜单栏「整机」拆分为「英特尔整机」（CPU+核显+SA）与「整机」（再加独显的真实整机功耗）",
                        "菜单栏独显/核显占用项改为显示型号简称（GT 650M / HD 4000）",
                        "独显/核显频率读不到时显示「待机」而非「–」",
                    ])
                    changelog("1.0.9", [
                        "移除菜单栏「更新日志…」入口（更新日志保留在关于页二级页面）",
                    ])
                    changelog("1.0.8", [
                        "修复点击「更新驱动」输密码后无反应：安装/卸载前先断开用户客户端，避免旧驱动被占用无法替换",
                        "驱动安装结果反馈更明确（区分已生效/需重启/失败原因）",
                    ])
                    changelog("1.0.7", [
                        "新增 SuperStateKext 硬件监控驱动：安装后免密码读取逐核实时频率（MSR）",
                        "kext 同时提供 RAPL 各域实时功率：整机 / CPU 核心 / 核显 GT / 内存 DRAM",
                        "修复 RAPL 能量单位换算错误（此前功耗数值偏大约 1.6 万倍）",
                        "功耗显示智能单位：<1W 自动用毫瓦，其余用瓦",
                        "监控项目新增：独显功耗（SMC 导轨实测）、核显功耗（RAPL）",
                        "驱动版本握手：旧版驱动显示「需要更新」而非误判为已加载；新增卸载驱动功能",
                        "工具页新增「硬件监控驱动」安装入口与状态指示（一次性授权，之后永久免授权）",
                        "CPU 核线程面板标题栏显示功耗摘要",
                        "状态面板内存小卡片改为主显示内存压力；仪表盘内存小卡支持点击切换占用率/压力",
                        "内存大卡片增加内存占用率信息行；核心温度条按温度高低变色",
                    ])
                    changelog("1.0.6", [
                        "修复独显/核显名称错误（显示为 nvAccelerator / IntelAccelerator）",
                        "攻克独显实时功耗：SMC PG0R 导轨功率免授权读取",
                        "内存压力改用内核真实压力，颜色按等级绿/橙/红，与活动监视器对齐",
                        "状态面板内存小卡片关联活跃内存占用并按等级变色",
                        "监控项目拆分：英特尔整机功耗监控（PCPT）与 CPU 功耗监控（PCPC）",
                        "非管理员模式频率固定显示基础频率；管理员模式实时频率保持不变",
                        "全程序按本机处理器指令集（SSE4.2 / AVX）优化编译",
                        "修复开机约 62 天后 CPU 统计溢出导致的潜在闪退",
                        "DMG 安装器新增拖动到应用程序提示，外观改用 App 图标",
                        "新增更新日志页",
                    ])
                    changelog("1.0.5", [
                        "活动监视器风格内存压力条，占用率/压力点击切换",
                        "Intel ARK 规格库：修正睿频 3.30GHz、核显最大频率 1200MHz",
                        "仪表盘集成 CPU / 内存详情大卡",
                        "新增硬件参数页（图吧工具箱风格）与关于页",
                        "菜单栏新增内存压力 / 进程数 / 线程数 / 句柄数",
                        "标签栏适配 macOS 26 液态玻璃",
                    ])
                    changelog("1.0.4", [
                        "状态面板 CPU 卡片恢复四核八线程展开视图",
                        "GPU 小卡拆分为独显 / 核显两张",
                        "新增进程数 / 线程数 / 句柄数统计",
                    ])
                    changelog("1.0.3", [
                        "菜单栏 GPU 频率拆分为核显频率 / 独显频率并带单位",
                    ])
                    changelog("1.0.2", [
                        "攻克独显实时频率（IOAccelerator 免授权）与独显功耗上限（SMC PG0C）",
                        "免授权 SMC 功率导轨：整机功耗 PCPT、CPU 核心功率 PCPC",
                    ])
                    changelog("1.0.1", [
                        "修复开启管理员模式后打开状态面板重复要求输入密码",
                        "修复独显断电（如关闭相册）时 100% 闪退（SMC 定点数溢出陷阱）",
                    ])
                    changelog("1.0.0", [
                        "首个版本：菜单栏系统监控、状态面板、温度 / 风扇、告警通知",
                    ])
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 460, height: 480)
    }

    private func changelog(_ version: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("v\(version)").font(.callout.bold())
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("·").font(.caption).foregroundStyle(.tertiary)
                    Text(item).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

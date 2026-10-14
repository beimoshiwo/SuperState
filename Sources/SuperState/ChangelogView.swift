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
                    // ===== 驱动（SuperStateKext）更新记录：逐版本 + 详细原因 =====
                    kextSection

                    Divider().padding(.vertical, 2)

                    changelog("1.0.15", [
                        "稳定性加固：系统休眠期间与唤醒后 5 秒过渡窗口内暂停 kext 硬件读取——OCLP 环境 GPU 驱动补丁不成熟，睡眠唤醒时 GPU 电源态剧烈切换，此时不碰设备内存（期间温度/风扇/功耗走 SMC 免授权兜底，功能不中断）",
                        "驱动更新记录区补全 v1–v4 历史：从 2026-10-12 首个版本（单位错误 / mp_cpus_call / dispatch 表 / 版本握手）起的完整脉络",
                    ])
                    changelog("1.0.14", [
                        "新增「CPU-Z」硬件信息区：处理器（型号/代号/工艺/TDP/睿频/缓存/指令集/封装）、主板（机型/固件/SMC/序列号/UUID）、内存（类型/速率/插槽）、SPD（每槽位容量/厂商/物料号）、显卡（显存/实时占用/温度/功耗/频率）；macOS 不提供的字段（如 SPD 详细时序）如实标注，不做猜测",
                        "新增系统级全局快捷键：⌘M 打开主界面 / ⌘⌥P 状态面板 / ⌘⌥F 网速悬浮窗（Carbon 热键，无需辅助功能权限，无需 App 在前台）",
                        "【关键修复】风扇调节真正生效：此前「装饰化」的根因是 macOS 对 SMC 写通道有权限保护（非特权进程写入一律被拒，界面静默失败），另有两个编码 bug（FS! 实际为 16 位、旧代码只写 1 字节导致手动模式从未开启；fpe2 目标值漏乘 4 导致转速只有 1/4）",
                        "风扇写入改为两级策略：免授权直连优先，被拒时经管理员授权执行（首次调节需输入密码，之后约 5 分钟内不再提示）；拖动滑杆自动合并请求",
                        "新增过热安全护栏：手动控扇期间 CPU/GPU 达到 95°C 自动恢复系统风扇模式；退出 App 同步恢复自动（失败时系统通知提醒）",
                        "更新日志新增「驱动（SuperStateKext）更新记录」区：逐版本改动与详细原因",
                    ])
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

    // MARK: 驱动（kext）更新记录

    private var kextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cpu.fill")
                Text("驱动（SuperStateKext）更新记录").font(.headline)
            }
            Text("硬件监控内核扩展的逐版本改动与详细原因（v1 始于 2026-10-12）；接口版本与 App 期望版本需一致才会显示「已就绪」。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            kextEntry("v9 · 接口 9 / 1.0.9", highlight: true, [
                "重新启用核显实时频率（方法 3），并把安全逻辑做扎实：每次重新取「当前」BAR0 + 双重电源态守卫 + 显式拒绝 0xFFFFFFFF/越界，绝不持有旧映射",
                "原因：v8 一刀切禁用虽稳但丢了功能；按「稳定与功能都要」重做",
            ])
            kextEntry("v8 · 接口 8 / 1.0.8", [
                "默认禁用方法 3（iGPU MMIO 读取）",
                "原因：审计确认它是 kext 里唯一的设备内存访问，存在无法彻底消除的 TOCTOU 竞态（电源态在检查后、读取前可能被切换 → 读失效映射 → PCIe 错误 → panic），过度保守地关掉以求绝对稳",
            ])
            kextEntry("v7 · 接口 7 / 1.0.7", highlight: true, [
                "【关键修复】根治导致系统五国语言重启的内核 panic",
                "根因：方法 0/1 高频调用 rdmsr_carefully 读 MSR；本机 i7-3615QM 无 DRAM RAPL（0x619），每次读必 #GP，高频 fault+recovery 在抢占交错下写坏内核栈指针 → kernel stack overflow",
                "修复：启动时一次性探测各 MSR 是否存在；热路径只对已确认存在的 MSR 用「裸 rdmsr」，彻底不走 recovery 机制",
            ])
            kextEntry("v6 · 接口 6 / 1.0.6", [
                "方法 3 改为每次调用重新定位 iGPU + 电源态守卫 + 用完立即释放（后被取证证明并非 panic 元凶，但保留更安全）",
            ])
            kextEntry("v5 · 接口 5 / 1.0.5", [
                "新增方法 3：核显（Intel HD Graphics）实时频率，只读图形 MMIO 的 GEN6_RPSTAT1",
                "移除 IOPCIDevice 依赖（该族符号第三方 kext 不可绑定、装不上）：改经 IOService 属性与虚方法取 BAR0",
            ])
            kextEntry("v4 · 接口 4 / 1.0.4", [
                "【关键修复】RAPL 能量单位读错位：ESU 在 bits 12:8（IVB 实测 14），此前误读 bits 3:0，功耗数值放大约 1.6 万倍（界面显示 23 万 W）；修复后实测整机 27.8W / CPU 核心 13.4W / 核显 8.0W",
                "打包流程改为每次强制重建 kext：此前「目录存在就跳过重建」导致修好的源码一直打包着旧的 v1 二进制（单位仍错、无版本接口）",
            ])
            kextEntry("v3 · 接口 3 / 1.0.3", [
                "修复 IOExternalMethodDispatch 字段顺序错误（结构输出大小被写成 0 → 方法 0/1 全部返回 kIOReturnBadArgument，action 根本未被调用）",
                "新增方法 2 版本握手 + App 三态识别（未安装 / 旧版 / 就绪），杜绝旧驱动被误判为最新；新增卸载驱动脚本与入口",
            ])
            kextEntry("v2 · 接口 2 / 1.0.2", [
                "修复 mp_cpus_call 无法绑定（现代 macOS 不再向第三方 kext 导出该 KPI）→ 改为只读「当前 CPU」MSR，App 侧用线程亲和性轮流绑定各逻辑 CPU 采集",
                "新增 CPUID 白名单：仅 SNB/IVB/HSW 启用 MSR 读取，其余机型直接返回不支持，避免误读触发 #GP",
            ])
            kextEntry("v1 · 接口 1", [
                "首个版本（2026-10-12，随 App 1.0.7 诞生）：方法 0 逐逻辑 CPU 实时频率（MSR 0x198 倍频）+ 方法 1 RAPL 能量计数（整机 / CPU 核心 / 核显 GT / DRAM），全程只读不写",
                "自带 _kmod_info 符号解决经典 kext 加载；已知缺陷：能量单位读错位（v4 修复）、无版本握手接口（v3 补上）",
            ])
        }
    }

    private func kextEntry(_ version: String, highlight: Bool = false, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(version).font(.callout.bold().monospacedDigit())
                if highlight {
                    Text("关键").font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
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
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(highlight ? 0.5 : 0.0), lineWidth: 1)
        )
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
# SuperState — 比 State 更强的 macOS 系统监控

SuperState 是一款常驻菜单栏的 macOS 系统监控应用，在 State（菜单栏 CPU/内存/温度/风扇/网速监控）的基础上，针对**配备独立显卡的 Mac** 做了核心增强：

## 相比 State 的增强点

| 能力 | State | SuperState |
|---|---|---|
| 核显 / 独显拆分显示 | ❌ 独显只在整体里笼统显示 | ✅ **两个独立模块**：核显（Intel HD）与独显（NVIDIA/AMD）各一张卡片 |
| GPU 占用率 | 有（不区分） | ✅ 双卡分别显示实时占用率 + 历史曲线，菜单栏可分别勾选「独显」「核显」 |
| 独显显存占用 | ❌ | ✅ 显示独显**已用 / 总量（MB）+ 进度条**，菜单栏可勾选 |
| CPU / GPU 频率 | ❌ | ✅ 新增：CPU 频率（标称免授权 2.3GHz，管理员模式实时睿频）、GPU 频率（独显实时，免授权） |
| CPU 每核占用 | 笼统整体 | ✅ 仪表盘 **CPU 卡片点击即展开 4 核 8 线程**实时占用（T0~T7 逐条） |
| CPU / GPU 温度 | ✅（免授权） | ✅ **同样免授权**：自研新版 SMC 协议客户端，CPU 整体/核心、核显/独显温度全部可读 |
| 风扇转速 | ✅（免授权） | ✅ **免授权**：双风扇实时转速（fpe2 定点解析） |
| 整机功耗 | ❌ | ✅ 仅此项需管理员模式（Intel 为 CPU+核显合并功耗 W） |
| CPU / 内存 / 磁盘 / 网络 | ✅ | ✅ 全部保留，另加磁盘读写速率、网络累计流量、开机时长、电池温度、热级别 |
| 历史曲线 | ❌ | ✅ 每个指标 300 点实时折线（含双 GPU 曲线） |
| 智能告警 | ❌ | ✅ CPU / 内存 / GPU 占用 / GPU 温度阈值超限系统通知 |
| 原生 / OCLP / 黑苹果识别 | ❌ | ✅ 自动分辨**原生 Mac / OCLP / OpenCore**（检测 OCLP 守护进程、Lilu kext），并按 CPU 推断**出厂(原生)机型** |
| 主程序窗口 | ✅ 有主界面 | ✅ **仪表盘**（实时监控数据卡片）+ 监控项目勾选 + 告警 + 工具，四页 |
| 菜单栏可配置 | ✅ | ✅ 显示项可勾选、中文/完整标签（CPU/核显/独显）、紧凑模式（10pt） |
| 快捷工具 | ✅ | ✅ 清空废纸篓、开机自启、网速悬浮窗、常用 App 快速启动 |

## 目录结构

```
源码/
└── SuperState/                 # Swift Package 工程
    ├── Package.swift
    ├── Info.plist              # 应用 Bundle 配置
    ├── build_app.sh            # 一键编译 + 打包 + 签名脚本
    ├── Assets/icon_1024.png    # 应用图标源文件
    └── Sources/SuperState/
        ├── main.swift          # 入口
        ├── AppDelegate.swift   # 生命周期 + --selfcheck 自检模式
        ├── Models.swift        # 数据结构 + 历史环形缓冲
        ├── HardwareProbe.swift # GPU 枚举（核显/独显）+ 显存/占用 + 电池温度
        ├── SystemMetrics.swift # CPU / 内存 / 磁盘 / 网络 / 进程
        ├── ThermalMetrics.swift# 热级别 + powermetrics（仅功耗，管理员）
        ├── SmcClient.swift     # 免授权新版 SMC 协议（温度/风扇）
        ├── Monitor.swift       # 每秒采集调度
        ├── Alerts.swift        # 阈值告警
        ├── QuickActions.swift  # 快捷工具 + 网速悬浮窗
        ├── StatusItemController.swift # 菜单栏
        ├── PanelView.swift     # 状态面板 UI
        ├── PlatformIdentity.swift # 原生/OCLP/黑苹果识别 + 出厂机型推断
        ├── DashboardView.swift # 主界面仪表盘
        ├── MainWindow.swift    # 主窗口（TabView）
        └── ChartsView.swift    # 折线图组件

产品/
└── SuperState.app              # 编译好的可运行应用
```

## 编译与打包（需要 macOS + Swift 工具链）

```bash
cd 源码/SuperState
./build_app.sh          # 输出 产品/SuperState.app 与 产品/SuperState.dmg
# 或手动：
swift build -c release
```

## 使用说明

## 安装

- **推荐（DMG）**：双击 `产品/SuperState.dmg` 挂载，把 **SuperState 拖入 Applications** 文件夹即可完成安装。
- 或直接双击 `产品/SuperState.app` 运行。首次启动如被 Gatekeeper 拦截，右键 → 打开。

## 使用说明

1. 启动后菜单栏以**上下排版**显示勾选参数（参考 State）：每个指标「数值在上、小标签在下」竖向成列、多列并排，
   最前面带一个小仪表图标，比横排「标签+数值」更省横向空间；点击弹出状态面板。
2. **状态面板**（点击菜单栏图标弹出）：概览卡片（CPU/内存/独显/核显/磁盘/网络，**点 CPU 卡片可展开 4 核 8 线程 T0~T7 实时占用**；
   内存卡为活动监视器同款**绿色内存压力条**）
   + **CPU 大卡片**（总体利用率、逻辑处理器逐条占用、当前/基础/睿频、内核数、逻辑处理器数、CPU 封装、虚拟化、缓存、进程数、线程数、句柄数、本次运行时间、免授权功率）
   + **内存大卡片**（**点击可在占用率/内存压力之间切换**、已用/总量、压力、Swap、活跃/联动/压缩、速度 MT/s、DDR 代数、插槽或焊接）
   + GPU 双卡详情 + 进程 + 告警 + 快捷工具。
3. 菜单栏图标 → 右键（或菜单）→ **「打开主界面…」**，主窗口分六页（macOS 26 液态玻璃 Tab 栏，旧系统自动降级毛玻璃）：
   - **仪表盘**：系统信息 + 实时监控数据卡片 + **CPU/内存大卡片** + CPU 核心温度 + 双 GPU 详情。
     **点击「CPU 占用」卡片可展开 / 收起 4 核 8 线程（T0~T7）实时占用**。
   - **硬件参数**（图吧工具箱风格）：系统 / 处理器（含官方规格：睿频、核显最大频率、TDP、插槽、指令集）/ 内存（每槽位）/ 图形（实时）/ 显示 / 存储 / 网络 / 电池（循环次数、健康度）详细检测。
   - **监控项目**：菜单栏可勾选 **CPU 占用/温度/频率/功耗、核显频率、独显频率（实时带单位）、内存压力、进程数、线程数、句柄数、内存、独显/核显占用与温度、独显显存、风扇、电池、网络、磁盘**；面板可勾选 GPU 双卡模块、GPU 曲线、进程、磁盘速率；带实时预览。
   - **告警**：开关 + CPU/内存/GPU 占用/GPU 温度阈值。
   - **工具**：管理员模式（powermetrics 实时频率）、开机自启、清空废纸篓、网速悬浮窗。
   - **关于**：软件信息、功能列表、版本号。

## 温度 / 风扇（免授权）与管理员模式（仅实时频率）

- 自研**新版 SMC 协议客户端**（`SmcClient.swift`）：80 字节结构、selector 2、子功能号置于 offset 42，
  **无需管理员密码**即可读取：CPU 整体（TC0P）与核心温度、核显（TG0P）/独显（TG1D）温度、
  双风扇转速（F0Ac/F1Ac，fpe2 定点 ÷4）、电池温度、独显功耗上限（PG0C，sp78 定点，单位 W）。
- **免授权功率导轨**（SMC）：`PCPT`（CPU 封装总功率）实测与 powermetrics 整机功耗 (CPUs+GT+SA) 几乎一致（偏差 < 0.6W）；
  `PCPC`（CPU 核心功率）、`PCPG`（核显功率，独显模式下读 0）。
- **独显实时频率（免授权）**：IOAccelerator 的 `PerformanceStatistics` 中名为
  `GPU Core Utilization` 的字段实际是 NVIDIA 驱动写入的**实时核心时钟（Hz）**
  （实测 GT 650M：空载 290~520MHz、满载 990MHz），除以 1e6 即为 MHz。
- **独显功耗**：NVIDIA/AMD 老卡在 macOS 上**没有实时功耗传感器通道**，界面显示 SMC 功率上限（PG0C，约 9.3W）并标注"上限"。
- **核显频率**：Intel 核显无频率上报通道；睿频/核显最大动态频率查 Intel 官方规格库（`CPUInfo.swift` 内置 Ivy Bridge / Haswell 移动版）。
- **只有 CPU 实时频率需要管理员模式**：开启后由 `Contents/Resources/superstate_start.sh` 启动
  powermetrics，并通过 `setsid`（start_new_session）让其进入全新会话常驻，避免授权进程退出时被连带终止。
  退出 SuperState 无需输入密码。

## 自检模式

```bash
产品/SuperState.app/Contents/MacOS/SuperState --selfcheck
```
打印当前 CPU/内存/磁盘/网络/双 GPU（占用、显存）/电池温度等全部指标后退出，用于验证数据通路。

## 已知限制

- 本机为 Intel 平台（MacBookPro16,4，GT 650M + HD 4000），显存读取依赖 IOKit 驱动属性；不同型号 Mac 属性名可能有差异，代码已做多级兜底。
- 温度/风扇/独显频率/独显功耗上限免授权；仅整机功耗需要管理员授权（见上）。
- 独显**实时功耗**在 NVIDIA/AMD 老卡上系统不提供，界面显示功率上限（SMC PG0C）；核显频率同样无上报通道，显示"–"。
- 该应用为本地开发构建（ad-hoc 签名），仅限本机使用。

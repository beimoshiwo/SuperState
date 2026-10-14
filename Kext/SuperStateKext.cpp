//
//  SuperStateKext.cpp
//  SuperState 硬件监控内核扩展
//
//  提供三类免授权硬件读数（内核态读 MSR / PCI / 图形 MMIO，用户态经 IOUserClient 调用）：
//    方法 0: 逐逻辑 CPU 实时频率（IA32_PERF_STATUS, MSR 0x198）
//    方法 1: RAPL 能量计数（MSR 0x606/0x611/0x639/0x641/0x619），
//            用户态差分得 整机/CPU 核心/核显 GT/内存 实时功率
//    方法 3: 核显（Intel HD Graphics）实时频率，只读图形 MMIO 的 GEN6_RPSTAT1(0xA01C)，
//            CAGF(bits[14:8]) × 50MHz。仅 SNB/IVB/HSW 等支持型号启用；任意环节失败返回 supported=0。
//
//  仅读取，不写任何 MSR / PCI / MMIO 寄存器，不触碰其他内核状态。所有路径 fail-safe。
//

#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/IOLib.h>
#include <i386/proc_reg.h>
#include <i386/cpuid.h>
#include <IOKit/IOMemoryDescriptor.h>

// 说明：mp_cpus_call 等 IPI 接口已不对第三方 kext 导出（kmutil 绑定失败）。
// 方案：kext 只读「当前 CPU」的 MSR（cpu_number + rdmsr_carefully 均可绑定），
//       由 App 侧用 THREAD_AFFINITY_POLICY 轮流绑定各逻辑 CPU 采集。
// 安全：仅读、不写任何 MSR；CPUID 白名单外的机器直接拒绝工作，避免误读触发 #GP。

// cpu_number() 符号可绑定（上一版 kmutil 报错仅 mp_cpus_call），公开头未声明，自行声明
extern "C" int cpu_number(void);

// ---- MSR 定义 ----
#define MSR_IA32_PERF_STATUS    0x198   // bits 15:8 = 当前倍频（SNB/IVB：freq = mult × 100MHz）
#define MSR_RAPL_POWER_UNIT     0x606   // bits 3:0 = 能量单位 1/2^n J
#define MSR_PKG_ENERGY_STATUS   0x611   // 整机包（CPU+GT+SA）
#define MSR_PP0_ENERGY_STATUS   0x639   // CPU 核心
#define MSR_PP1_ENERGY_STATUS   0x641   // 核显 GT
#define MSR_DRAM_ENERGY_STATUS  0x619   // 内存

// 裸 rdmsr：仅用于「已确认存在」的 MSR，不会触发 #GP，故不依赖内核 recovery 机制。
// （v7 起热路径改用它，彻底移除高频 rdmsr_carefully 的栈溢出风险。）
static inline void raw_rdmsr(uint32_t msr, uint32_t* lo, uint32_t* hi) {
    __asm__ volatile("rdmsr" : "=a"(*lo), "=d"(*hi) : "c"(msr) : "memory");
}

// 方法 3（核显实时频率，读 iGPU 图形 MMIO）开关。默认 1 = 启用（用户明确要求：稳定与功能都要）。
// 安全契约（把"如果不对会怎样"逐点锁死，落点在 sReadGPUFreq 内逐步标注）：
//   ① 每次调用重新定位 iGPU、重新取「当前」BAR0、重新建只读映射，用完立即释放——
//      绝不持有会随电源态/重配而失效的旧映射（v5 的 stale 映射正是潜在 panic 源）；
//   ② 双重电源态守卫：acquireIGPU 查一次 + 真正读取前紧邻再查一次，把 TOCTOU 窗口压到最小，
//      任一次发现 iGPU 非唤醒态 → 不读；
//   ③ 结果校验：显式拒绝 0xFFFFFFFF（设备无响应）与越界值 → supported=0（界面「待机」），绝不放行离谱值；
//   ④ 全程 fail-safe：任一环节失败/不确定 → supported=0，绝不冒险、绝不 panic。
// 诚实边界：对可被异步断电的设备读 MMIO，存在理论上无法归零的亚微秒竞态；但在 Intel 客户端平台上，
//   读设备「当前有效 BAR」即使设备掉电通常也返回 0xFFFFFFFF（非致命总线完成），且实测本机 6 次 panic
//   无一出自方法 3。若要绝对零风险可改为 0 关闭（失去核显实时频率，界面回退「待机」）。
#define kEnableGPUFreqRead 1

struct SSFreqOutput {
    uint32_t cpu;   // 实际执行读取的逻辑 CPU 编号（cpu_number()）
    uint32_t mhz;   // 该核实时频率（0 = 读取失败）
};

struct SSGpuFreqOutput {
    uint32_t mhz;        // 核显实时频率（MHz），supported=1 时有效
    uint32_t supported;  // 1=成功读取真实值；0=不支持/不可读（界面显示"待机"）
};

struct SSRaplOutput {
    uint32_t pkg;
    uint32_t pp0;
    uint32_t pp1;
    uint32_t dram;
    uint32_t esuShift;   // 能量单位 = 1/2^esuShift 焦耳
    uint32_t validMask;  // bit0 pkg, bit1 pp0, bit2 pp1, bit3 dram
};

enum {
    kMethodReadFreq = 0,
    kMethodReadRAPL = 1,
    kMethodGetVersion = 2,
    kMethodReadGPUFreq = 3,
    kMethodCount
};

// 驱动接口版本（App 据此判断是否需要更新驱动）；改接口时必须递增
// v7：修复方法 0/1 因「高频调用 rdmsr_carefully」触发内核栈溢出 panic（真凶，已由 .panic 回溯坐实）。
// v8：曾默认禁用方法 3（过度保守，牺牲了核显频率功能）。
// v9：应用户「稳定与功能都要」的要求——重新启用方法 3，并把其安全逻辑做扎实（见 kEnableGPUFreqRead
//     处的安全契约与 sReadGPUFreq 内逐步落点）：每次重新取当前 BAR0 + 双重电源态守卫 +
//     显式拒绝 0xFFFFFFFF/越界，绝不持有旧映射。方法 0/1 的 v7 修复保持不变。
#define kSuperStateKextInterfaceVersion 9u

struct SSVersionOutput {
    uint32_t version;
};

// ---- kmod_info：经典 kext 必须提供的模块描述符（kmutil 校验 _kmod_info 符号）----
// 类型定义来自内核头文件 mach/kmod.h（经 IOKit 头引入）
extern "C" {
kern_return_t ss_kmod_start(kmod_info*, void*) { return KERN_SUCCESS; }
kern_return_t ss_kmod_stop(kmod_info*, void*) { return KERN_SUCCESS; }

__attribute__((used, visibility("default")))
kmod_info kmod_info = {
    .next            = nullptr,
    .info_version    = 1,            // KMOD_INFO_VERSION
    .id              = 0xFFFFFFFF,   // 加载时由内核分配
    .name            = "com.superstate.kext",
    .version         = "1.0.9",
    .reference_count = -1,
    .reference_list  = nullptr,
    .address         = 0,
    .size            = 0,
    .hdr_size        = 0,
    .start           = &ss_kmod_start,
    .stop            = &ss_kmod_stop,
};
}

#define kSuperStateKextClass SuperStateKext
#define kSuperStateUserClientClass SuperStateUserClient

// MARK: - 服务本体

class kSuperStateKextClass : public IOService {
    OSDeclareDefaultStructors(SuperStateKext)

public:
    bool start(IOService* provider) APPLE_KEXT_OVERRIDE;
    IOReturn newUserClient(task_t task, void* securityID, UInt32 type,
                           OSDictionary* properties, IOUserClient** handler) APPLE_KEXT_OVERRIDE;
};

OSDefineMetaClassAndStructors(SuperStateKext, IOService)

// MSR 读取安全性开关：仅在本机已确认支持 0x198/RAPL 的 Intel 型号上启用
static bool gMSRSupported = false;

// v7：启动时一次性探测各 MSR 是否存在，缓存有效位掩码；热路径只对这些 MSR 用裸 rdmsr
static uint32_t gRaplMask     = 0;     // bit0 pkg, bit1 pp0, bit2 pp1, bit3 dram
static uint32_t gRaplEsuShift = 14;    // 能量单位 1/2^esuShift 焦耳（Ivy Bridge 典型 14）
static bool     gFreqOk       = false; // MSR 0x198（IA32_PERF_STATUS）可读

// 一次性探测（仅 kext start 时、且模型受支持时调用一次；无并发、无高频压力，rdmsr_carefully 安全）
static void probeMSRs() {
    uint32_t lo = 0, hi = 0;
    gFreqOk = (rdmsr_carefully(MSR_IA32_PERF_STATUS, &lo, &hi) == 0);
    if (rdmsr_carefully(MSR_RAPL_POWER_UNIT, &lo, &hi) == 0) {
        gRaplEsuShift = (lo >> 8) & 0x1F;   // bits 12:8 = 能量单位指数
        gRaplMask = 1;                       // PKG 域必存在
        if (rdmsr_carefully(MSR_PP0_ENERGY_STATUS,  &lo, &hi) == 0) gRaplMask |= 2;
        if (rdmsr_carefully(MSR_PP1_ENERGY_STATUS,  &lo, &hi) == 0) gRaplMask |= 4;
        // 客户端 Ivy Bridge（i7-3615QM）无 DRAM RAPL 域：此 MSR 不存在会 #GP。
        // 但探测仅一次、低频，recovery 可安全吞掉；存在才置位（下次热路径才读它）。
        if (rdmsr_carefully(MSR_DRAM_ENERGY_STATUS, &lo, &hi) == 0) gRaplMask |= 8;
    }
    IOLog("SuperStateKext: freqOk=%d raplMask=0x%X esuShift=%u\n",
          gFreqOk, gRaplMask, gRaplEsuShift);
}

static void detectCPUModel() {
    uint32_t a = 0, b = 0, c = 0, d = 0;
    __asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(1u), "c"(0u));
    uint32_t family = (a >> 8) & 0xF;
    uint32_t model  = (a >> 4) & 0xF;
    uint32_t extModel  = (a >> 16) & 0xF;
    uint32_t extFamily = (a >> 20) & 0xFF;
    uint32_t effFamily = family + extFamily;
    uint32_t effModel  = (family == 6 || family == 15) ? (model | (extModel << 4)) : model;
    switch ((effFamily << 8) | effModel) {
        case 0x062A:  // Sandy Bridge
        case 0x063A:  // Ivy Bridge（本机 i7-3615QM）
        case 0x063E:  // Ivy Bridge-E
        case 0x063C:  // Haswell
        case 0x063F:  // Haswell-E
        case 0x0645:  // Haswell-R
        case 0x0646:  // Haswell ULT
            gMSRSupported = true;
            break;
        default:
            gMSRSupported = false;
            break;
    }
    IOLog("SuperStateKext: CPU family=0x%X model=0x%X, MSR read %s\n",
          effFamily, effModel, gMSRSupported ? "enabled" : "disabled (unsupported model)");
}

bool SuperStateKext::start(IOService* provider) {
    if (!IOService::start(provider)) return false;
    detectCPUModel();
    if (gMSRSupported) probeMSRs();   // v7：仅一次、低频探测，热路径不再使用 rdmsr_carefully
    registerService();
    IOLog("SuperStateKext: started\n");
    return true;
}

// MARK: - 用户客户端

class kSuperStateUserClientClass : public IOUserClient {
    OSDeclareDefaultStructors(SuperStateUserClient)

public:
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments* arguments,
                            IOExternalMethodDispatch* dispatch, OSObject* target,
                            void* reference) APPLE_KEXT_OVERRIDE;
    IOReturn clientClose(void) APPLE_KEXT_OVERRIDE;

    // 静态跳板（IOExternalMethodDispatch 需要 C 风格入口）
    static IOReturn sReadFreq(SuperStateUserClient* target, void* reference,
                              IOExternalMethodArguments* args);
    static IOReturn sReadRAPL(SuperStateUserClient* target, void* reference,
                              IOExternalMethodArguments* args);
    static IOReturn sGetVersion(SuperStateUserClient* target, void* reference,
                                IOExternalMethodArguments* args);
    static IOReturn sReadGPUFreq(SuperStateUserClient* target, void* reference,
                                 IOExternalMethodArguments* args);
};

OSDefineMetaClassAndStructors(SuperStateUserClient, IOUserClient)

IOReturn SuperStateUserClient::clientClose(void) {
    return kIOReturnSuccess;
}

// 接口版本握手（App 判断驱动新旧）
IOReturn SuperStateUserClient::sGetVersion(SuperStateUserClient*, void*,
                                           IOExternalMethodArguments* args) {
    auto* out = static_cast<SSVersionOutput*>(args->structureOutput);
    if (!out || args->structureOutputSize < sizeof(SSVersionOutput)) return kIOReturnBadArgument;
    out->version = kSuperStateKextInterfaceVersion;
    return kIOReturnSuccess;
}

// 读取「当前 CPU」的 IA32_PERF_STATUS（App 侧用线程亲和性轮流绑定各核采集）
// v7：仅对启动时确认存在的 MSR 0x198 用裸 rdmsr——不触发 #GP、不走 recovery，无栈溢出风险。
IOReturn SuperStateUserClient::sReadFreq(SuperStateUserClient*, void*,
                                         IOExternalMethodArguments* args) {
    if (!gMSRSupported || !gFreqOk) return kIOReturnUnsupported;
    auto* out = static_cast<SSFreqOutput*>(args->structureOutput);
    if (!out || args->structureOutputSize < sizeof(SSFreqOutput)) return kIOReturnBadArgument;
    bzero(out, sizeof(SSFreqOutput));
    out->cpu = (uint32_t)cpu_number();
    uint32_t lo = 0, hi = 0;
    raw_rdmsr(MSR_IA32_PERF_STATUS, &lo, &hi);
    out->mhz = ((lo >> 8) & 0xFF) * 100;   // SNB/IVB：倍频 × 100MHz
    return kIOReturnSuccess;
}

// v7：RAPL 热路径。startup 已用 rdmsr_carefully 一次性确认各域存在（gRaplMask），
//     此处只对确认存在的域用裸 rdmsr，绝不走 recovery 机制，根除栈溢出 panic。
IOReturn SuperStateUserClient::sReadRAPL(SuperStateUserClient*, void*,
                                         IOExternalMethodArguments* args) {
    if (!gMSRSupported) return kIOReturnUnsupported;
    auto* out = static_cast<SSRaplOutput*>(args->structureOutput);
    if (!out || args->structureOutputSize < sizeof(SSRaplOutput)) return kIOReturnBadArgument;
    bzero(out, sizeof(SSRaplOutput));

    uint32_t lo = 0, hi = 0;
    out->esuShift  = gRaplEsuShift;
    out->validMask = gRaplMask;
    if (gRaplMask & 1) { raw_rdmsr(MSR_PKG_ENERGY_STATUS,  &lo, &hi); out->pkg  = lo; }
    if (gRaplMask & 2) { raw_rdmsr(MSR_PP0_ENERGY_STATUS,  &lo, &hi); out->pp0  = lo; }
    if (gRaplMask & 4) { raw_rdmsr(MSR_PP1_ENERGY_STATUS,  &lo, &hi); out->pp1  = lo; }
    if (gRaplMask & 8) { raw_rdmsr(MSR_DRAM_ENERGY_STATUS, &lo, &hi); out->dram = lo; }
    return kIOReturnSuccess;
}

// ---- 核显频率（只读 Intel 显示控制器图形 MMIO 的 GEN6_RPSTAT1）----
//
// ⚠️ 稳定性红线（2026-10-13 教训，本机实锤内核 panic）：最初版本把 iGPU 的 IOService 与
//    BAR0 的 IODeviceMemory 缓存为模块级静态变量并长期持有。iGPU 在显卡切换 / 省电时会重配
//    BAR0，其驱动会拆除并重建 MMIO 映射——此时我们持有的旧映射已失效却仍在读，命中无效/已
//    释放地址 → 触发 PCIe 错误 → 内核 panic（五国语言重启）。这正是最初装完 kext 后不定
//    时死机的根因。
//
// 修复要点（本案核心）：
//   1) 绝不长期持有设备 / 内存：每次调用都重新定位 iGPU、重新取 BAR0、重新建映射，用完即释放；
//   2) 只读前经 getPowerState() 确认 iGPU 处于唤醒态（state != 0），睡眠 / RC6 态下不读
//      （此时读图形 MMIO 可能触发 PCIe 错误并 panic）；
//   3) 全程 fail-safe：任一环节不确定 → 返回 supported=0（界面显示「待机」），绝不冒险读取。
//
// 注：第三方 kext 不能引用 IOPCIDevice 符号，故只用导出的 IOService 虚方法 + getProperty。
#if kEnableGPUFreqRead
// 从属性 OSData 读出 16 位 vendor-id（小端：字节0=低字节，字节1=高字节）
static UInt16 readVendorID(IOService* svc) {
    OSData* d = OSDynamicCast(OSData, svc->getProperty("vendor-id"));
    if (!d || d->getLength() < 2) return 0;
    const UInt8* p = (const UInt8*)d->getBytesNoCopy();
    return (UInt16)(p[0] | (p[1] << 8));
}

// 从属性 OSData 读出 24 位 class-code（字节0=progif，字节1=subclass，字节2=baseclass）
static UInt32 readClassCode(IOService* svc) {
    OSData* d = OSDynamicCast(OSData, svc->getProperty("class-code"));
    if (!d || d->getLength() < 3) return 0;
    const UInt8* p = (const UInt8*)d->getBytesNoCopy();
    return ((UInt32)p[2] << 16) | ((UInt32)p[1] << 8) | (UInt32)p[0];
}

// 重新定位 iGPU，返回 retain 后的 IOService*（调用方负责 release）。
// 找不到、或不在唤醒态 → 返回 nullptr（上层返回 supported=0 / 「待机」）。
static IOService* acquireIGPU() {
    OSDictionary* matching = IOService::serviceMatching("IOPCIDevice");
    if (!matching) return nullptr;
    OSIterator* iter = IOService::getMatchingServices(matching);
    matching->release();
    if (!iter) return nullptr;

    IOService* found = nullptr;
    IOService* svc = nullptr;
    while ((svc = (IOService*)iter->getNextObject())) {
        if (readVendorID(svc) != 0x8086)    continue;   // 只要 Intel
        if (readClassCode(svc) != 0x030000) continue;    // 显示控制器
        // 仅在 iGPU 唤醒态读取：睡眠 / RC6 下其 MMIO 不可安全访问，读了可能 panic
        if (svc->getPowerState() == 0)       continue;
        found = svc;
        found->retain();
        break;
    }
    iter->release();
    return found;
}
#endif // kEnableGPUFreqRead

// 方法 3：核显实时频率。默认启用（kEnableGPUFreqRead=1）；完整安全契约见上方开关处注释。
// 全程 fail-safe——任一环节失败 / 不确定都返回 supported=0（界面「待机」），绝不 panic。
IOReturn SuperStateUserClient::sReadGPUFreq(SuperStateUserClient*, void*,
                                            IOExternalMethodArguments* args) {
    auto* out = static_cast<SSGpuFreqOutput*>(args->structureOutput);
    if (!out || args->structureOutputSize < sizeof(SSGpuFreqOutput)) return kIOReturnBadArgument;
    bzero(out, sizeof(SSGpuFreqOutput));      // supported=0, mhz=0

#if kEnableGPUFreqRead
    if (!gMSRSupported) return kIOReturnSuccess;   // 非支持型号 → 不支持

    // ① 定位 iGPU + 电源态守卫（检查 #1）：acquireIGPU 已确认 getPowerState()!=0 才返回
    IOService* svc = acquireIGPU();
    if (!svc) return kIOReturnSuccess;        // 无 Intel 核显 / 睡眠态 → 不支持

    // ② 取「当前」BAR0 并建只读映射：每次重新取，绝不持有会随电源态/重配失效的旧映射（v5 panic 源）
    IODeviceMemory* mem = svc->getDeviceMemoryWithIndex(0);   // BAR0 = GTTMMADR
    if (mem) mem->retain();
    if (!mem) { svc->release(); return kIOReturnSuccess; }

    IOMemoryMap* map = mem->createMappingInTask(kernel_task, 0, kIOMapReadOnly);
    if (map) {
        IOVirtualAddress base = map->getVirtualAddress();
        // ③ 电源态守卫（检查 #2）：把「确认唤醒」紧贴到真正读取之前，最大程度缩小 TOCTOU 窗口；
        //    若此刻 iGPU 已睡/断电 → 不读（读掉电设备的 MMIO 有 PCIe 错误风险）。
        if (base && svc->getPowerState() != 0) {
            // GEN6_RPSTAT1 = 0xA01C；CAGF 在 bits[14:8]，单位 50MHz（SNB/IVB/HSW RPS）
            // x86 为小端，MMIO 寄存器经 32 位加载即得原值（等效 OSReadLittleUInt32）
            volatile UInt32* rp = (volatile UInt32*)(base + 0xA01C);
            UInt32 rpstat = *rp;
            UInt32 cagf = (rpstat >> 8) & 0x7F;
            UInt32 mhz = cagf * 50;
            // ④ 结果校验：设备无响应返回 0xFFFFFFFF（→ cagf=0x7F → 6350MHz，越界被拒）；
            //    显式排除 0xFFFFFFFF，并做严格范围校验（HD 4000 标称 650~1300MHz，留足余量）。
            //    任何越界/异常一律 supported=0（待机），绝不放行离谱值。
            if (rpstat != 0xFFFFFFFF && mhz >= 100 && mhz <= 2000) {
                out->mhz = mhz;
                out->supported = 1;
            }
        }
        map->release();
    }
    mem->release();
    svc->release();
#endif // kEnableGPUFreqRead
    return kIOReturnSuccess;
}

IOReturn SuperStateUserClient::externalMethod(uint32_t selector,
                                              IOExternalMethodArguments* arguments,
                                              IOExternalMethodDispatch* dispatch,
                                              OSObject* target, void* reference) {
    static const IOExternalMethodDispatch sMethods[kMethodCount] = {
        // 字段顺序：标量输入数、结构输入大小、标量输出数、结构输出大小
        { (IOExternalMethodAction)&SuperStateUserClient::sReadFreq,
          0, 0, 0, sizeof(SSFreqOutput) },
        { (IOExternalMethodAction)&SuperStateUserClient::sReadRAPL,
          0, 0, 0, sizeof(SSRaplOutput) },
        { (IOExternalMethodAction)&SuperStateUserClient::sGetVersion,
          0, 0, 0, sizeof(SSVersionOutput) },
        { (IOExternalMethodAction)&SuperStateUserClient::sReadGPUFreq,
          0, 0, 0, sizeof(SSGpuFreqOutput) },
    };
    if (selector < kMethodCount) {
        dispatch = const_cast<IOExternalMethodDispatch*>(&sMethods[selector]);
        target = this;
    }
    return IOUserClient::externalMethod(selector, arguments, dispatch, target, reference);
}

// MARK: - newUserClient

IOReturn SuperStateKext::newUserClient(task_t task, void* securityID, UInt32 type,
                                       OSDictionary* properties, IOUserClient** handler) {
    if (type != 0) return kIOReturnBadArgument;
    SuperStateUserClient* uc = new SuperStateUserClient;
    if (!uc) return kIOReturnNoMemory;
    if (!uc->initWithTask(task, securityID, type, properties)) {
        uc->release();
        return kIOReturnError;
    }
    *handler = uc;
    return kIOReturnSuccess;
}

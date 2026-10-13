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
#define kSuperStateKextInterfaceVersion 5u

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
    .version         = "1.0.4",
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
IOReturn SuperStateUserClient::sReadFreq(SuperStateUserClient*, void*,
                                         IOExternalMethodArguments* args) {
    if (!gMSRSupported) return kIOReturnUnsupported;
    auto* out = static_cast<SSFreqOutput*>(args->structureOutput);
    if (!out || args->structureOutputSize < sizeof(SSFreqOutput)) return kIOReturnBadArgument;
    bzero(out, sizeof(SSFreqOutput));
    out->cpu = (uint32_t)cpu_number();
    uint32_t lo = 0, hi = 0;
    if (rdmsr_carefully(MSR_IA32_PERF_STATUS, &lo, &hi) == 0) {
        out->mhz = ((lo >> 8) & 0xFF) * 100;   // SNB/IVB：倍频 × 100MHz
    }
    return kIOReturnSuccess;
}

static inline uint32_t readEnergy(uint32_t msr, bool* ok) {
    uint32_t lo = 0, hi = 0;
    if (rdmsr_carefully(msr, &lo, &hi) == 0) {
        *ok = true;
        return lo;  // 能量计数在低位 32 位，用户态做回绕差分
    }
    *ok = false;
    return 0;
}

IOReturn SuperStateUserClient::sReadRAPL(SuperStateUserClient*, void*,
                                         IOExternalMethodArguments* args) {
    if (!gMSRSupported) return kIOReturnUnsupported;
    auto* out = static_cast<SSRaplOutput*>(args->structureOutput);
    if (!out || args->structureOutputSize < sizeof(SSRaplOutput)) return kIOReturnBadArgument;
    bzero(out, sizeof(SSRaplOutput));

    uint32_t lo = 0, hi = 0;
    if (rdmsr_carefully(MSR_RAPL_POWER_UNIT, &lo, &hi) != 0) {
        return kIOReturnNotFound;  // 该 CPU 不支持 RAPL
    }
    // 能量单位在 bits 12:8（1/2^ESU 焦耳；Ivy Bridge 实测 ESU=14）；bits 3:0 是功率单位，勿混用
    out->esuShift = (lo >> 8) & 0x1F;

    bool ok = false;
    out->pkg = readEnergy(MSR_PKG_ENERGY_STATUS, &ok);  if (ok) out->validMask |= 1;
    out->pp0 = readEnergy(MSR_PP0_ENERGY_STATUS, &ok);  if (ok) out->validMask |= 2;
    out->pp1 = readEnergy(MSR_PP1_ENERGY_STATUS, &ok);  if (ok) out->validMask |= 4;
    out->dram = readEnergy(MSR_DRAM_ENERGY_STATUS, &ok); if (ok) out->validMask |= 8;
    return kIOReturnSuccess;
}

// ---- 核显频率（只读 Intel 显示控制器图形 MMIO 的 GEN6_RPSTAT1）----
// 缓存找到的核显服务与其 MMIO 描述符（retain 持有，kext 生命周期内有效；
// 内部 GPU 不会在运行时热插拔）。仅在未找到时扫描一次，找到后直接复用。
//
// 关键约束：第三方 kext 无法绑定 IOPCIDevice 的符号（Apple 不予导出，kmutil 会
//   报 undefined symbol __ZN11IOPCIDevice9metaClassE 等而加载失败）。因此这里：
//   1) 用 IOService::serviceMatching("IOPCIDevice") 取回 IOService*，绝不强转 IOPCIDevice；
//   2) 经导出的 IORegistryEntry::getProperty 读 vendor-id / class-code 属性判断是否为
//      Intel 显示控制器（vendor 0x8086 + class 0x030000），不碰任何 PCI config 寄存器；
//   3) 经导出的 IOService::getDeviceMemoryWithIndex(0)（虚方法，vtable 落入 IOPCIDevice
//      实现）取 BAR0 图形 MMIO，全程仅读不写、fail-safe，任一环节失败即返回 false。
static IOService*       gIGPU = nullptr;
static IODeviceMemory* gIGPUMem = nullptr;
static bool             gIGPUSearched = false;

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

static bool locateIGPU() {
    if (gIGPUMem)        return true;          // 已找到并缓存
    if (gIGPUSearched)   return false;         // 已扫描但未找到，不再重复
    gIGPUSearched = true;

    OSDictionary* matching = IOService::serviceMatching("IOPCIDevice");
    if (!matching) return false;
    OSIterator* iter = IOService::getMatchingServices(matching);
    matching->release();
    if (!iter) return false;

    IOService* svc = nullptr;
    while ((svc = (IOService*)iter->getNextObject())) {
        if (readVendorID(svc) != 0x8086)  continue;   // 只要 Intel
        if (readClassCode(svc) != 0x030000) continue;  // 显示控制器
        gIGPU = svc;
        gIGPU->retain();
        break;
    }
    iter->release();
    if (!gIGPU) return false;

    gIGPUMem = gIGPU->getDeviceMemoryWithIndex(0);     // BAR0 = GTTMMADR
    if (gIGPUMem) gIGPUMem->retain();
    return gIGPUMem != nullptr;
}

// 方法 3：核显实时频率。fail-safe——任一环节失败都返回 supported=0。
IOReturn SuperStateUserClient::sReadGPUFreq(SuperStateUserClient*, void*,
                                            IOExternalMethodArguments* args) {
    auto* out = static_cast<SSGpuFreqOutput*>(args->structureOutput);
    if (!out || args->structureOutputSize < sizeof(SSGpuFreqOutput)) return kIOReturnBadArgument;
    bzero(out, sizeof(SSGpuFreqOutput));      // supported=0, mhz=0

    if (!gMSRSupported) return kIOReturnSuccess;   // 非支持型号 → 不支持
    if (!locateIGPU())  return kIOReturnSuccess;   // 无 Intel 核显 → 不支持

    // 只读映射核显图形 MMIO（BAR0），仅读不写
    IOMemoryMap* map = gIGPUMem->createMappingInTask(kernel_task, 0, kIOMapReadOnly);
    if (!map) return kIOReturnSuccess;
    IOVirtualAddress base = map->getVirtualAddress();
    if (!base) { map->release(); return kIOReturnSuccess; }

    // GEN6_RPSTAT1 = 0xA01C；CAGF 在 bits[14:8]，单位 50MHz（SNB/IVB/HSW RPS）
    // x86 为小端，MMIO 寄存器经 32 位加载即得原值（等效 OSReadLittleUInt32）
    volatile UInt32* rp = (volatile UInt32*)(base + 0xA01C);
    UInt32 rpstat = *rp;
    UInt32 cagf = (rpstat >> 8) & 0x7F;
    UInt32 mhz = cagf * 50;
    map->release();

    // 严格范围校验：HD 4000 标称 650~1300MHz，留足余量拒绝异常值
    if (mhz >= 100 && mhz <= 2000) {
        out->mhz = mhz;
        out->supported = 1;
    }
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

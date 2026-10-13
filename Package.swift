// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SuperState",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SuperState",
            path: "Sources/SuperState",
            // 指令集优化：按本机处理器（Ivy Bridge，支持 SSE4.1/4.2 + AVX，无 AVX2）
            // 以 core-avx-i 目标 CPU 编译，让 LLVM 生成 AVX/SSE4.2 指令
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-target-cpu", "-Xfrontend", "core-avx-i"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)

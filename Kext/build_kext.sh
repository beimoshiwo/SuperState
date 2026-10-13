#!/bin/bash
# SuperStateKext 构建脚本：命令行 clang -mkernel 构建（无需完整 Xcode）
set -e
cd "$(dirname "$0")"

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
KHEADERS="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
OUT="SuperStateKext.kext/Contents"

echo "==> 编译 SuperStateKext.cpp（SSE4.2 / AVX 指令集，匹配本机 Ivy Bridge）"
clang++ -arch x86_64 \
  -mkernel -nostdlib -fno-builtin -fno-exceptions -fno-rtti \
  -fno-stack-protector -mno-soft-float \
  -msse4.2 -mavx \
  -O2 -Wall -DKERNEL -D_KERNEL \
  -isysroot "$SDK" \
  -I"$KHEADERS" \
  -c SuperStateKext.cpp -o /tmp/SuperStateKext.o

echo "==> 链接 kext 二进制"
clang++ -arch x86_64 \
  -mkernel -nostdlib \
  -isysroot "$SDK" \
  -Xlinker -kext \
  /tmp/SuperStateKext.o \
  -L"$SDK/usr/lib" -lkmodc++ -lkmod \
  -o /tmp/SuperStateKext

mkdir -p "$OUT/MacOS"
cp /tmp/SuperStateKext "$OUT/MacOS/SuperStateKext"
cp Info.plist "$OUT/Info.plist"

echo "==> ad-hoc 签名（本机 Kext Signing 已禁用，加载不校验签名）"
codesign --force --sign - "SuperStateKext.kext" 2>/dev/null || true

echo "构建完成: SuperStateKext.kext"
file "$OUT/MacOS/SuperStateKext"

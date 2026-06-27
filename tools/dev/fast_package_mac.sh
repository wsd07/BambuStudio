#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tools/dev/fast_package_mac.sh [-a arm64|x86_64] [-c Release|Debug] [-j jobs]

快速刷新本地可双击的 macOS BambuStudio.app。

适用场景：
  - 只修改 C++/资源/配置后，需要快速给用户测试。
  - 现有 build/<arch> 已由 BuildMac.sh 完整配置过。

不适用场景：
  - CMake 配置、依赖、架构、部署目标变化。
  - 第一次构建或 build/<arch> 不存在。
EOF
}

arch="$(uname -m)"
config="Release"
jobs="${CMAKE_BUILD_PARALLEL_LEVEL:-8}"

while getopts "a:c:j:h" opt; do
    case "$opt" in
        a) arch="$OPTARG" ;;
        c) config="$OPTARG" ;;
        j) jobs="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$project_dir/build/$arch"
staged_dir="$build_dir/BambuStudio"
src_app="$build_dir/src/BambuStudio.app"
dst_app="$staged_dir/BambuStudio.app"

if [ ! -d "$build_dir" ]; then
    echo "找不到构建目录：$build_dir"
    echo "请先运行一次完整构建，例如：./BuildMac.sh -s -x -a $arch -c $config -t 14.0"
    exit 2
fi

if [ ! -f "$build_dir/CMakeCache.txt" ]; then
    echo "构建目录缺少 CMakeCache.txt：$build_dir"
    echo "请先运行一次完整构建。"
    exit 2
fi

echo "快速构建 BambuStudio 目标..."
cmake --build "$build_dir" --config "$config" --target BambuStudio --parallel "$jobs"

if [ ! -d "$src_app" ]; then
    echo "构建产物不存在：$src_app"
    exit 3
fi

echo "刷新可双击 App 包..."
mkdir -p "$staged_dir"

clone_copy_dir() {
    local source_dir="$1"
    local target_dir="$2"
    rm -rf "$target_dir"
    if ! cp -cpR "$source_dir" "$target_dir" 2>/dev/null; then
        cp -pR "$source_dir" "$target_dir"
    fi
}

resources_path="$(readlink "$src_app/Contents/Resources" || true)"

if [ ! -d "$dst_app" ]; then
    clone_copy_dir "$src_app" "$dst_app"
fi

# 普通 C++ 修改只刷新可执行文件，避免每次复制数万项资源。
mkdir -p "$dst_app/Contents/MacOS"
cp -cp "$src_app/Contents/MacOS/BambuStudio" "$dst_app/Contents/MacOS/BambuStudio"
if [ -f "$src_app/Contents/Info.plist" ]; then
    cp -cp "$src_app/Contents/Info.plist" "$dst_app/Contents/Info.plist"
fi

# 快速包仅供本机开发测试，直接链接项目资源目录；资源改动无需再次复制。
if [ -n "$resources_path" ]; then
    rm -rf "$dst_app/Contents/Resources"
    ln -s "$resources_path" "$dst_app/Contents/Resources"
    echo "开发资源已链接：$resources_path"
fi

find "$dst_app" -name '.DS_Store' -delete

echo "完成：$dst_app"

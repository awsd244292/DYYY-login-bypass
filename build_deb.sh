#!/bin/bash
#
# DYYY 一键构建脚本
# 注意：本脚本必须在「已配置 Theos + iOS SDK + ldid」的 macOS 上运行。
# 本仓库是 iOS Theos/Logos Tweak，产出的 .deb 为 iphoneos-arm 包，
# 需在越狱 / TrollStore / TrollFools 环境下注入到抖音 (Aweme)。
#
# 用法：
#   ./build_deb.sh            # 默认方案（有根）
#   ./build_deb.sh rootless   # 无根（rootless）设备
#   ./build_deb.sh roothide   # roothide 方案
#
set -e

SCHEME="${1:-default}"

case "$SCHEME" in
  default)  MAKE_ARGS="" ;;
  rootless) MAKE_ARGS="SCHEME=rootless" ;;
  roothide) MAKE_ARGS="SCHEME=roothide" ;;
  -h|--help)
    echo "用法: $0 [default|rootless|roothide]"
    exit 0
    ;;
  *)
    echo "未知方案: $SCHEME"
    echo "用法: $0 [default|rootless|roothide]"
    exit 1
    ;;
esac

if ! command -v make >/dev/null 2>&1; then
  echo "[错误] 未找到 make，请先安装 Xcode 命令行工具 (xcode-select --install)"
  exit 1
fi

if [ -z "$THEOS" ]; then
  echo "[提示] 未检测到 \$THEOS 环境变量，尝试使用默认路径 /opt/theos"
  export THEOS="/opt/theos"
fi

if [ ! -d "$THEOS" ]; then
  echo "[错误] 未找到 Theos，请先安装：https://theos.dev/docs/installation"
  exit 1
fi

echo "==> 清理旧构建"
make clean || true

echo "==> 开始构建 DYYY (scheme: $SCHEME)"
# FINALPACKAGE=1 关闭调试符号，产出正式包
make package FINALPACKAGE=1 $MAKE_ARGS

DEB=$(ls -t packages/*.deb 2>/dev/null | head -n1)
if [ -z "$DEB" ]; then
  echo "[错误] 构建未产出 .deb 文件，请检查上方编译日志"
  exit 1
fi

echo ""
echo "==> 构建成功: $DEB"
echo "==> 将该 .deb 通过 Sileo / Filza 安装，或用 TrollFools 注入到抖音 (Aweme)。"

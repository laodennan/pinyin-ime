#!/usr/bin/env bash
# 在 macOS runner 上用官方 librime（与 iOS 端同版本）的 rime_deployer
# 预编译 SharedData，生成 build/*.bin，使键盘首次启动免部署。见 PLAN.md 2.2。
#
# 依赖：LIBRIME_VERSION 环境变量（默认 1.16.1）。
# 资产命名已于 2026-11-04 按 librime 1.16.1 Release 资产列表核实并填为默认值：
#   rime-de4700e-macOS-universal.tar.bz2（内含 bin/rime_deployer）
#   rime-deps-de4700e-macOS-universal.tar.bz2
# 下载 URL 形如：
#   https://github.com/rime/librime/releases/download/1.16.1/rime-de4700e-macOS-universal.tar.bz2
# （首次试跑第 10 号运行就是死在这两个变量未设——脚本的 :? 守卫直接退出。）
set -euo pipefail

LIBRIME_VERSION="${LIBRIME_VERSION:-1.16.1}"
LIBRIME_ASSET_RIME="${LIBRIME_ASSET_RIME:-rime-de4700e-macOS-universal.tar.bz2}"
LIBRIME_ASSET_DEPS="${LIBRIME_ASSET_DEPS:-rime-deps-de4700e-macOS-universal.tar.bz2}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$ROOT/Keyboard/SharedData"
DEPS="$ROOT/.deps/librime-$LIBRIME_VERSION"

# 注意真实包内布局（2026-11-04 在本机解包核实，勿再猜）：
# - rime 包整体在 dist/ 下：部署器 dist/bin/rime_deployer，库 dist/lib/（含 rime-plugins/）。
# - deps 包为顶层 bin/、include/、lib/（leveldb/yaml-cpp/marisa/glog/opencc 等）。
# 第 12 号 CI 运行即死在旧脚本按 $DEPS/bin/rime_deployer 找部署器的错误路径上。
if [[ ! -x "$DEPS/dist/bin/rime_deployer" ]]; then
  mkdir -p "$DEPS"
  base="https://github.com/rime/librime/releases/download/$LIBRIME_VERSION"
  curl -fsSL -o "$DEPS/rime.tar.bz2" "$base/$LIBRIME_ASSET_RIME"
  curl -fsSL -o "$DEPS/rime-deps.tar.bz2" "$base/$LIBRIME_ASSET_DEPS"
  tar -xjf "$DEPS/rime.tar.bz2" -C "$DEPS"
  tar -xjf "$DEPS/rime-deps.tar.bz2" -C "$DEPS"
fi

echo "== deployer =="
ls -la "$DEPS/dist/bin/rime_deployer"

export DYLD_LIBRARY_PATH="$DEPS/dist/lib:$DEPS/lib:${DYLD_LIBRARY_PATH:-}"
export DYLD_FALLBACK_LIBRARY_PATH="$DEPS/dist/lib:$DEPS/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
"$DEPS/dist/bin/rime_deployer" --build "$DATA"

echo "== precompiled bins =="
ls -la "$DATA/build/"
du -sh "$DATA"

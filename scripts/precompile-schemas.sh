#!/usr/bin/env bash
# 在 macOS runner 上用官方 librime（与 iOS 端同版本）的 rime_deployer
# 预编译 SharedData，生成 build/*.bin，使键盘首次启动免部署。见 PLAN.md 2.2。
#
# 依赖：LIBRIME_VERSION 环境变量（默认 1.16.1）。
# 资产命名（已核对 1.16.1 Release）：rime-<hash>-macOS-universal.tar.bz2 内含 bin/rime_deployer。
# TODO(首次试跑): 资产文件名中的 git hash 需按目标版本 Release 页填实到 LIBRIME_ASSET_RIME /
# LIBRIME_ASSET_DEPS 两个变量；下载 URL 形如：
#   https://github.com/rime/librime/releases/download/1.16.1/rime-de4700e-macOS-universal.tar.bz2
set -euo pipefail

LIBRIME_VERSION="${LIBRIME_VERSION:-1.16.1}"
LIBRIME_ASSET_RIME="${LIBRIME_ASSET_RIME:?set to the rime-*-macOS-universal.tar.bz2 asset name of the pinned release}"
LIBRIME_ASSET_DEPS="${LIBRIME_ASSET_DEPS:?set to the rime-deps-*-macOS-universal.tar.bz2 asset name of the pinned release}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$ROOT/Keyboard/SharedData"
DEPS="$ROOT/.deps/librime-$LIBRIME_VERSION"

if [[ ! -x "$DEPS/bin/rime_deployer" ]]; then
  mkdir -p "$DEPS"
  base="https://github.com/rime/librime/releases/download/$LIBRIME_VERSION"
  curl -fsSL -o "$DEPS/rime.tar.bz2" "$base/$LIBRIME_ASSET_RIME"
  curl -fsSL -o "$DEPS/rime-deps.tar.bz2" "$base/$LIBRIME_ASSET_DEPS"
  tar -xjf "$DEPS/rime.tar.bz2" -C "$DEPS"
  tar -xjf "$DEPS/rime-deps.tar.bz2" -C "$DEPS"
fi

export DYLD_FALLBACK_LIBRARY_PATH="$DEPS/dist/lib:${DYLD_FALLBACK_LIBRARY_PATH:-}"
"$DEPS/bin/rime_deployer" --build "$DATA"

echo "== precompiled bins =="
ls -la "$DATA/build/"
du -sh "$DATA"

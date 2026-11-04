#!/usr/bin/env bash
# 组装键盘扩展的 SharedData 目录：拉取锁定版本的雾凇拼音（rime-ice），
# 剔除无关大文件，保留其 LICENSE 与出处。产物不入 git（见 .gitignore）。
#
# 用法：bash scripts/fetch-rime-ice.sh <rime-ice-commit-sha>
# 草稿状态：词库取舍（是否剔除 tencent 大词库）按 PLAN.md 2.1 的内存预案，
# 首次试跑后在此定版。
set -euo pipefail

RIME_ICE_COMMIT="${1:?usage: fetch-rime-ice.sh <commit-sha>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DST="$ROOT/Keyboard/SharedData"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --quiet https://github.com/iDvel/rime-ice.git "$WORK/rime-ice"
git -C "$WORK/rime-ice" checkout --quiet "$RIME_ICE_COMMIT"

rm -rf "$DST"
mkdir -p "$DST"

# 雾凇是自包含方案：拷贝方案/词库/lua/opencc/默认配置。
# - t9.schema.yaml 保留（v2 资产），v1 应用层 T9 不依赖它。
# - build/ 由 precompile-schemas.sh 生成，此处不带（仓库内为空目录）。
rsync -a \
  --exclude '.git' \
  --exclude '.github' \
  --exclude 'others' \
  --exclude 'build' \
  "$WORK/rime-ice/" "$DST/"

echo "Assembled SharedData from rime-ice@$RIME_ICE_COMMIT"
du -sh "$DST"

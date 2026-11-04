#!/usr/bin/env bash
# 组装键盘扩展的 SharedData 目录：拉取锁定版本的雾凇拼音（rime-ice），
# 剔除无关大文件，保留其 LICENSE 与出处。产物不入 git（见 .gitignore）。
#
# 用法：bash scripts/fetch-rime-ice.sh <rime-ice-commit-sha>
# 词库取舍已定版（2026-11-04 晚，PLAN 9.6）：剔除 tencent 大词库
# （98 万词条，占总词条量约 52%）以压键盘扩展的内存峰值——保留
# base+ext+8105+others，上游文件本身不动，只改组装产物。
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
# - cn_dicts/tencent.dict.yaml 在此排除（词库瘦身，见下方 import 行处理）。
rsync -a \
  --exclude '.git' \
  --exclude '.github' \
  --exclude 'others' \
  --exclude 'build' \
  --exclude 'cn_dicts/tencent.dict.yaml' \
  "$WORK/rime-ice/" "$DST/"

# 词库瘦身（PLAN 9.6）：删掉组装产物 rime_ice.dict.yaml 的 import_tables
# 里引用 tencent 的那一行。锁定 commit 上已核对：该文件内 "cn_dicts/tencent"
# 只出现在这一行（其余 tencent 字样都在注释/文档与被排除的 others/ 里，
# 与导入无关）。用 grep -v 而非 sed -i，避开 BSD/GNU sed 的 -i 语法差异；
# 上游 clone 在 $WORK 里，改的只是 $DST 产物。删不掉就当场失败，
# 不许带着大词库静默出包。
grep -v 'cn_dicts/tencent' "$DST/rime_ice.dict.yaml" > "$DST/rime_ice.dict.yaml.slim"
mv "$DST/rime_ice.dict.yaml.slim" "$DST/rime_ice.dict.yaml"
if grep -q 'cn_dicts/tencent' "$DST/rime_ice.dict.yaml"; then
  echo "error: tencent import still present in assembled rime_ice.dict.yaml" >&2
  exit 1
fi
if [[ -e "$DST/cn_dicts/tencent.dict.yaml" ]]; then
  echo "error: tencent.dict.yaml still present in assembled SharedData" >&2
  exit 1
fi

echo "Assembled SharedData from rime-ice@$RIME_ICE_COMMIT (tencent dict excluded)"
du -sh "$DST"

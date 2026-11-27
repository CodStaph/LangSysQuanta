#!/usr/bin/env bash
# tools/install-hooks.sh — 一键挂载 L2 hooks（SDD-Plus §7 第 2 条：hooks 不随克隆传播）
#
# 用法：
#   bash tools/install-hooks.sh          # 安装 commit-msg / pre-push 到 .git/hooks/
#   bash tools/install-hooks.sh --check  # CI 校验模式：只验证三件套在库且语法正确，不写 .git
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
check_only=0
[ "${1:-}" = "--check" ] && check_only=1

for h in commit-msg pre-push; do
  src="$root/tools/hooks/$h"
  if [ ! -f "$src" ]; then
    echo "install-hooks: FAIL missing tools/hooks/$h" >&2
    exit 1
  fi
  bash -n "$src" || { echo "install-hooks: FAIL syntax error in tools/hooks/$h" >&2; exit 1; }
  if [ "$check_only" -eq 1 ]; then
    echo "install-hooks: --check OK: tools/hooks/$h (syntax)"
    continue
  fi
  dst="$(git -C "$root" rev-parse --git-path hooks)/$h"
  cp "$src" "$dst"
  chmod +x "$dst"
  echo "install-hooks: installed $dst"
done

if [ "$check_only" -eq 0 ]; then
  echo "install-hooks: done（克隆本仓库后必须执行本脚本；CI 校验其存在性，SDD-Plus §7 第 2 条）"
fi
exit 0

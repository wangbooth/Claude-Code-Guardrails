#!/usr/bin/env bash
set -euo pipefail

mode="${1:-stop}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD?)"
protected='^(main|master|dev|release($|[/-].*))$'
if [[ "$branch" =~ $protected ]]; then
  # 受保护分支不做 squash（防止改历史）
  exit 0
fi

count="$(git log --oneline --grep '^checkpoint:' 2>/dev/null | wc -l | tr -d ' ' 2>/dev/null || echo '0')"
[ "$count" -gt 1 ] || exit 0

# 仅在“本地 ahead 或无上游”的情况下改历史，避免已推送后的奇怪冲突
if git rev-parse --symbolic-full-name --verify -q @{u} >/dev/null 2>&1; then
  # 有上游时，只在 ahead>0 时操作
  if ! git status -sb 2>/dev/null | grep -q 'ahead' 2>/dev/null; then
    exit 0
  fi
fi

last_changes="$(git log --oneline --grep '^checkpoint:' 2>/dev/null | head -3 | cut -d' ' -f2- | tr '\n' ', ' | sed 's/, $//' 2>/dev/null || echo 'changes')"
suffix="$( [ "$mode" = "compact" ] && echo "conversation compacted - " || true )"
git reset --soft "HEAD~${count}"
git commit -m "task: ${suffix}${last_changes} - $(date +'%Y-%m-%d')"
echo "Squashed ${count} checkpoint commits into one."

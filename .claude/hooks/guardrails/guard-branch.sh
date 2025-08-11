#!/usr/bin/env bash
set -euo pipefail

# 检查是否在 git 仓库中
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  >&2 echo "⚠️  Current project is not managed by Git."
  >&2 echo "   当前项目未使用 Git 管理。"
  >&2 echo ""
  >&2 echo "It's recommended to initialize a Git repository for version control and code protection:"
  >&2 echo "建议初始化 Git 仓库以便进行版本控制和代码保护："
  >&2 echo "  git init"
  >&2 echo "  git config user.name \"Your Name\""
  >&2 echo "  git config user.email \"your.email@example.com\""
  >&2 echo "  git add ."
  >&2 echo "  git commit -m \"Initial commit\""
  >&2 echo ""
  >&2 echo "Operation cancelled. Please initialize Git repository first."
  >&2 echo "已取消操作。请先初始化 Git 仓库。"
  exit 2
fi

# 检查是否有未提交的更改
if ! git diff-index --quiet HEAD 2>/dev/null || ! git diff --staged --quiet 2>/dev/null; then
  >&2 echo "⚠️  Detected uncommitted changes in the repository."
  >&2 echo "   检测到仓库中有未提交的更改。"
  >&2 echo ""
  >&2 echo "There are uncommitted changes that may be lost if AI overwrites them."
  >&2 echo "存在未提交的更改，如果被 AI 覆盖可能导致代码丢失。"
  >&2 echo ""
  >&2 echo "Consider committing these changes first:"
  >&2 echo "建议先提交这些更改："
  >&2 echo "  git add ."
  >&2 echo "  git commit -m \"Save work in progress\""
  >&2 echo ""
  >&2 echo "Operation cancelled. Please commit your changes first."
  >&2 echo "已取消操作。请先提交您的更改。"
  exit 2
fi

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD?)"
protected='^(main|master|dev|release($|[/-].*))$'

if [[ "$branch" =~ $protected ]]; then
  >&2 echo "⚠️  Branch '$branch' is protected."
  >&2 echo "   当前分支 '$branch' 已受保护。"
  >&2 echo ""
  >&2 echo "It's recommended to create/switch to a vibe branch before making changes:"
  >&2 echo "建议创建/切换到 vibe 分支再修改，例如："
  >&2 echo "  git checkout -b vibe/$(date +%Y%m%d%H%M%S)-claude"
  >&2 echo ""
  >&2 echo "Operation cancelled. Please switch to a vibe branch and retry."
  >&2 echo "已取消操作。请切换到 vibe 分支后重试。"
  exit 2
fi

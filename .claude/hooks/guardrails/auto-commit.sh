#!/usr/bin/env bash
set -euo pipefail

# 读取 Claude 传入的 JSON 负载，从中拿到文件路径和工具名
payload="$(cat || true)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
tool="$(printf '%s' "$payload" | jq -r '.tool_name // "UnknownTool"')"

# 不在 git 仓库或拿不到文件名就跳过
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
[ -n "${file:-}" ] || exit 0

# 检查文件是否被 gitignore，如果是则备份
if [ -f "$file" ] && git check-ignore "$file" >/dev/null 2>&1; then
    backup_dir=".claude/backups"
    mkdir -p "$backup_dir"
    
    # 创建时间戳备份
    timestamp="$(date +'%Y%m%d-%H%M%S')"
    backup_file="$backup_dir/$(basename "$file").$timestamp"
    cp "$file" "$backup_file"
    
    # 确保 .claude/backups/ 在 .gitignore 中
    if ! grep -q "^\.claude/backups/" .gitignore 2>/dev/null; then
        # Ensure .gitignore ends with a newline before appending
        [ -s .gitignore ] && [ "$(tail -c1 .gitignore)" != "" ] && echo "" >> .gitignore
        echo ".claude/backups/" >> .gitignore
    fi
    
    # 友好提示用户（中英文）
    echo "📦 Backup Notice: '$file' is a gitignored file. A backup has been saved to '$backup_file' before claude code modification."
    echo "📦 备份提醒: '$file' 是 gitignore 文件，claude code 修改前已备份到 '$backup_file'"
    echo "   If you do not want claude code to modify this file, you can configure it in permissions.deny in .claude/settings.json."
    echo "   如不希望 claude code 修改此文件，可在 .claude/settings.json 的 permissions.deny 中配置"
    echo ""

fi

# 仅对该文件做 add（包含删除/重命名的场景）
git add -A -- "$file" 2>/dev/null || true

# 如果本次没有待提交变更就退出
git diff --cached --quiet && exit 0

# 生成精简的变更文件清单（最多 3 个）
changed="$(git diff --cached --name-only | head -3 | tr '\n' ',' | sed 's/,$//')"
now="$(date +'%Y%m%d%H%M%S')"

git commit -m "checkpoint: ${tool} ${changed:-$file} - ${now}"

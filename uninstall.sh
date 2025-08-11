#!/usr/bin/env bash
# Claude Code Guardrails - uninstaller
# 功能：从 settings.json 移除 guardrails hooks（备份+幂等），并可清理脚本目录
set -euo pipefail

GLOBAL=0
TARGET="${PWD}"
KEEP_SCRIPTS=0
VERBOSE=0

usage() {
  cat <<'USAGE'
Usage: uninstall.sh [--global] [--target <dir>] [--keep-scripts] [-v]
  --global        Uninstall globally (~/.claude/settings.json) | 卸载全局 (~/.claude/settings.json)
  --target DIR    Uninstall from specified project directory (default: current) | 卸载指定项目目录（默认当前目录）
  --keep-scripts  Keep installed script files | 保留已安装的脚本文件
  -v, --verbose   Verbose logging | 输出更详细日志
USAGE
}

log() { [ "$VERBOSE" -eq 1 ] && echo "[guardrails] $*" >&2 || true; }

command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq is required but not installed. | 需要 jq 但未安装。" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global|-g) GLOBAL=1; shift;;
    --target|-t) 
      if [ -z "${2:-}" ] || [[ "${2:-}" =~ ^- ]]; then
        echo "ERROR: --target requires a directory argument / --target 需要目录参数" >&2
        exit 2
      fi
      TARGET="$2"; shift 2;;
    --keep-scripts) KEEP_SCRIPTS=1; shift;;
    -v|--verbose) VERBOSE=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1 / 未知选项: $1" >&2; usage; exit 2;;
  esac
done

if [ "$GLOBAL" -ne 1 ] && [ ! -d "$TARGET" ]; then
  echo "ERROR: Target directory does not exist: $TARGET | 目标目录不存在：$TARGET" >&2
  exit 1
fi

# 解析路径
if [ "$GLOBAL" -eq 1 ]; then
  SETTINGS_DIR="$HOME/.claude"
  SETTINGS_PATH="$SETTINGS_DIR/settings.json"
  DEST_HOOKS_DIR="$SETTINGS_DIR/hooks/guardrails"
  CMD_GUARD="$DEST_HOOKS_DIR/guard-branch.sh"
  CMD_AUTO="$DEST_HOOKS_DIR/auto-commit.sh"
  CMD_SQUASH="$DEST_HOOKS_DIR/squash-checkpoints.sh"
else
  TARGET="$(cd "$TARGET" && pwd)"
  SETTINGS_DIR="$TARGET/.claude"
  SETTINGS_PATH="$SETTINGS_DIR/settings.json"
  DEST_HOOKS_DIR="$SETTINGS_DIR/hooks/guardrails"
  CMD_GUARD='$CLAUDE_PROJECT_DIR/.claude/hooks/guardrails/guard-branch.sh'
  CMD_AUTO='$CLAUDE_PROJECT_DIR/.claude/hooks/guardrails/auto-commit.sh'
  CMD_SQUASH='$CLAUDE_PROJECT_DIR/.claude/hooks/guardrails/squash-checkpoints.sh'
fi

[ -f "$SETTINGS_PATH" ] || { echo "Settings file not found: $SETTINGS_PATH, no uninstallation needed. | 没有找到 $SETTINGS_PATH，无需卸载。" >&2; exit 0; }
cp -f "$SETTINGS_PATH" "$SETTINGS_PATH.bak.$(date +%Y%m%d%H%M%S)"
log "Backed up settings.json | 已备份 settings.json"

CMDS_JSON="$(mktemp)"
jq -n --arg a "$CMD_GUARD" --arg b "$CMD_AUTO" --arg c "$CMD_SQUASH" '
  [$a,$b,$c] | map(select(length>0))
' > "$CMDS_JSON"

FILTERED_TMP="$(mktemp)"
jq --slurpfile cmds "$CMDS_JSON" '
  def strip_cmds(arr):
    (arr // []) | map(
      .hooks = ((.hooks // []) | map(select((.command as $c | ($cmds[0] | index($c)) | not))))
    )
    | map(select((.hooks // []) | length > 0));

  .hooks.PreToolUse  = strip_cmds(.hooks.PreToolUse)  |
  .hooks.PostToolUse = strip_cmds(.hooks.PostToolUse) |
  .hooks.Stop        = strip_cmds(.hooks.Stop)        |
  .hooks.PreCompact  = strip_cmds(.hooks.PreCompact)
' "$SETTINGS_PATH" > "$FILTERED_TMP"

mv "$FILTERED_TMP" "$SETTINGS_PATH"
rm -f "$CMDS_JSON"

if [ "$KEEP_SCRIPTS" -eq 0 ] && [ -d "$DEST_HOOKS_DIR" ]; then
  rm -rf "$DEST_HOOKS_DIR"
  log "Deleted script directory: $DEST_HOOKS_DIR | 已删除脚本目录：$DEST_HOOKS_DIR"
fi

echo "✅ Uninstallation completed: $([ "$GLOBAL" -eq 1 ] && echo 'Global | 全局' || echo 'Project | 项目')"
echo "   Settings: $SETTINGS_PATH"
echo "   Backup: $(ls -1 "$SETTINGS_PATH".bak.* 2>/dev/null | tail -n1 || echo 'None | 无')"

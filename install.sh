#!/usr/bin/env bash
# Claude Code Guardrails - installer
# 功能：复制脚本 + 生成/合并 settings.json（备份+去重+幂等）
set -euo pipefail

# -------- CLI 选项 --------
GLOBAL=0
TARGET="${PWD}"
VERBOSE=0

usage() {
  cat <<'USAGE'
Usage: install.sh [--global] [--target <dir>] [-v]
  --global        Install globally (~/.claude/settings.json) / 安装到全局
  --target DIR    Install to specified project directory (default: current directory) / 安装到指定项目目录（默认当前目录）
  -v, --verbose   More verbose output / 输出更详细日志
USAGE
}

log() { [ "$VERBOSE" -eq 1 ] && echo "[guardrails] $*" >&2 || true; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global|-g) GLOBAL=1; shift;;
    --target|-t) 
      if [ -z "${2:-}" ] || [[ "${2:-}" =~ ^- ]]; then
        echo "ERROR: --target requires a directory argument / --target 需要目录参数" >&2
        exit 2
      fi
      TARGET="$2"; shift 2;;
    -v|--verbose) VERBOSE=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1 / 未知选项: $1" >&2; usage; exit 2;;
  esac
done

# -------- 依赖检查 --------
command -v jq >/dev/null 2>&1 || { 
  echo "ERROR: jq is required but not installed." >&2
  echo "       需要 jq 但未安装。" >&2
  echo "       Install with: brew install jq  OR  apt-get install -y jq" >&2
  echo "       安装命令：brew install jq  或者  apt-get install -y jq" >&2
  exit 1
}

log "Mode: $([ "$GLOBAL" -eq 1 ] && echo Global || echo Project) | Target: $([ "$GLOBAL" -eq 1 ] && echo "$HOME/.claude" || echo "$TARGET")"

# -------- 路径初始化 --------
# 检测是否通过管道执行（远程安装）
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "bash" ]; then
  # 远程安装模式：下载必要文件到临时目录
  log "Remote installation mode detected / 检测到远程安装模式"
  TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TEMP_DIR"' EXIT
  
  BASE_URL="https://raw.githubusercontent.com/wangbooth/claude-code-guardrails/main"
  SRC_HOOKS_DIR="$TEMP_DIR/.claude/hooks"
  mkdir -p "$SRC_HOOKS_DIR"
  
  log "Downloading hook scripts / 下载 hook 脚本"
  for script in guard-branch.sh auto-commit.sh squash-checkpoints.sh; do
    if ! curl -fsSL "$BASE_URL/.claude/hooks/guardrails/$script" -o "$SRC_HOOKS_DIR/$script"; then
      echo "ERROR: Failed to download $script" >&2
      echo "       下载 $script 失败" >&2
      exit 1
    fi
    log "Downloaded: $script / 已下载: $script"
  done
else
  # 本地安装模式：使用脚本所在目录
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SRC_HOOKS_DIR="$SCRIPT_DIR/.claude/hooks"
  if [ ! -d "$SRC_HOOKS_DIR" ]; then
    echo "ERROR: Source hooks directory not found: $SRC_HOOKS_DIR" >&2
    echo "       未找到源 hooks 目录：$SRC_HOOKS_DIR" >&2
    echo "       Please run this script from the repository root directory." >&2
    echo "       请从仓库根目录执行此脚本。" >&2
    exit 1
  fi
fi

if [ "$GLOBAL" -eq 1 ]; then
  SETTINGS_DIR="$HOME/.claude"
  SETTINGS_PATH="$SETTINGS_DIR/settings.json"
  DEST_HOOKS_DIR="$SETTINGS_DIR/hooks/guardrails"
  # 全局安装：写入“绝对路径”命令
  CMD_GUARD="$DEST_HOOKS_DIR/guard-branch.sh"
  CMD_AUTO="$DEST_HOOKS_DIR/auto-commit.sh"
  CMD_SQUASH="$DEST_HOOKS_DIR/squash-checkpoints.sh"
else
  # 项目安装
  if [ ! -d "$TARGET" ]; then
    echo "ERROR: Target directory does not exist: $TARGET" >&2
    echo "       目标目录不存在：$TARGET" >&2
    exit 1
  fi
  TARGET="$(cd "$TARGET" && pwd)"
  SETTINGS_DIR="$TARGET/.claude"
  SETTINGS_PATH="$SETTINGS_DIR/settings.json"
  DEST_HOOKS_DIR="$SETTINGS_DIR/hooks/guardrails"
  # 项目安装：写入“项目变量路径”，便于在不同机器工作
  CMD_GUARD='$CLAUDE_PROJECT_DIR/.claude/hooks/guardrails/guard-branch.sh'
  CMD_AUTO='$CLAUDE_PROJECT_DIR/.claude/hooks/guardrails/auto-commit.sh'
  CMD_SQUASH='$CLAUDE_PROJECT_DIR/.claude/hooks/guardrails/squash-checkpoints.sh'
fi

mkdir -p "$SETTINGS_DIR" "$DEST_HOOKS_DIR"

# -------- 复制脚本（备份差异文件）--------
copy_one() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    cp -f "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
    log "Backed up: $(basename "$dst").bak.* / 已备份: $(basename "$dst").bak.*"
  fi
  install -m 0755 "$src" "$dst"
  log "Installed: $(basename "$dst") / 已安装: $(basename "$dst")"
}

copy_one "$SRC_HOOKS_DIR/guard-branch.sh"        "$DEST_HOOKS_DIR/guard-branch.sh"
copy_one "$SRC_HOOKS_DIR/auto-commit.sh"      "$DEST_HOOKS_DIR/auto-commit.sh"
copy_one "$SRC_HOOKS_DIR/squash-checkpoints.sh"  "$DEST_HOOKS_DIR/squash-checkpoints.sh"

# -------- 生成 Guardrails 片段 --------
GUARDRAILS_JSON="$(mktemp)"

jq -n --arg guard "$CMD_GUARD" --arg auto "$CMD_AUTO" --arg squash "$CMD_SQUASH" '
{
hooks: {
    PreToolUse: [
    { matcher:"Write|Edit|MultiEdit", hooks:[
        {type:"command", command:$guard, timeout:10}
    ]}
    ],
    PostToolUse: [
    { matcher:"Write|Edit|MultiEdit", hooks:[
        {type:"command", command:$auto, timeout:30}
    ]}
    ],
    Stop: [
    { hooks:[ {type:"command", command:$squash, timeout:30} ] }
    ],
    PreCompact: [
    { hooks:[ {type:"command", command:$squash, timeout:60} ] }
    ]
}
}' > "$GUARDRAILS_JSON"


# -------- 合并到 settings.json（备份+去重+幂等）--------
[ -f "$SETTINGS_PATH" ] || echo '{}' > "$SETTINGS_PATH"
cp -f "$SETTINGS_PATH" "$SETTINGS_PATH.bak.$(date +%Y%m%d%H%M%S)"
log "Backed up settings.json / 已备份 settings.json"

MERGED_TMP="$(mktemp)"

jq -s '
  # 对单条目里的 hooks 去重（按 type|command|timeout）
  def uniq_hooks(a):
    (a // []) | unique_by((.type // "") + "|" + (.command // "") + "|" + ((.timeout // 0)|tostring));

  # 将非数组规范化为数组（防用户误配）
  def as_array(x): if (x|type) == "array" then x else (if x == null then [] else [x] end) end;

  # 查找匹配的 matcher 索引
  def find_matcher_index(arr; matcher):
    [range(0; arr|length)] | map(select((arr[.].matcher // null) == (matcher // null))) | first // null;

  # 合并事件数组：按 matcher 追加，同 matcher 的第一条里合并 hooks（不删除用户已有条目）
  def hooks_merge(old; new):
    (as_array(old)) as $o |
    (as_array(new)) as $n |
    reduce $n[] as $m (
      $o;
      find_matcher_index($o; $m.matcher) as $idx |
      if $idx != null then
        .[$idx].hooks = uniq_hooks( (.[$idx].hooks // []) + ($m.hooks // []) )
      else
        . + [ (if $m.matcher then { matcher: $m.matcher } else {} end) + { hooks: uniq_hooks($m.hooks // []) } ]
      end
    );

  .[0] as $old | .[1] as $new |
  ($old.hooks // {}) as $base |
  # 用 + 保留旧配置的其它顶层键；hooks 用合并后的结果覆盖
  $old + { hooks:
    ( $base
      + { PreToolUse:  hooks_merge($base.PreToolUse;  $new.hooks.PreToolUse)  }
      + { PostToolUse: hooks_merge($base.PostToolUse; $new.hooks.PostToolUse) }
      + { Stop:        hooks_merge($base.Stop;        $new.hooks.Stop)        }
      + { PreCompact:  hooks_merge($base.PreCompact;  $new.hooks.PreCompact)  }
    )
  }
' "$SETTINGS_PATH" "$GUARDRAILS_JSON" > "$MERGED_TMP"



mv "$MERGED_TMP" "$SETTINGS_PATH"
rm -f "$GUARDRAILS_JSON"

echo "✅ Installation completed: $([ "$GLOBAL" -eq 1 ] && echo 'Global' || echo 'Project') / 安装完成：$([ "$GLOBAL" -eq 1 ] && echo '全局' || echo '项目')"
echo "   Settings: $SETTINGS_PATH"
echo "   Scripts : $DEST_HOOKS_DIR"
echo "   Backup  : $(ls -1 "$SETTINGS_PATH".bak.* 2>/dev/null | tail -n1 || echo 'None / 无')"

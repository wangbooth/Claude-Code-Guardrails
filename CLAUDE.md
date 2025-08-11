# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository implements **Claude Code Guardrails** - a set of protective hooks that prevent accidental code loss and provide safe development workflows when using Claude Code. The system provides branch protection, automatic checkpointing, and safe commit squashing through Claude Code hooks.

## Architecture

The guardrails system consists of three main components that integrate with Claude Code's hook system:

### Hook Scripts (`claude/hooks/`)

- **`guard-branch.sh`** - Prevents writes to protected branches (main/master/dev/release*) by exiting with code 2, blocking tool execution and suggesting feature branch creation
- **`auto-commit.sh`** - Creates precise checkpoint commits after each Write/Edit/MultiEdit operation, staging only the modified file(s)
- **`squash-checkpoints.sh`** - Consolidates multiple checkpoint commits into clean task commits during Stop/PreCompact events

### Hook Configuration (`claude/settings.json`)

Defines the hook integration points:
- **PreToolUse**: Branch protection before Write/Edit/MultiEdit operations
- **PostToolUse**: Automatic checkpoint creation after Write/Edit/MultiEdit operations
- **Stop/PreCompact**: Commit squashing when conversations end or are compacted

### Installation System

- **`install.sh`** - Merges guardrails hooks into existing `.claude/settings.json` with backup, deduplication, and idempotent operation
- **`uninstall.sh`** - Safely removes guardrails hooks while preserving other user hooks

## Key Development Commands

### Installation
```bash
# Project-level installation (current directory)
curl -fsSL https://raw.githubusercontent.com/wangbooth/claude-code-guardrails/main/install.sh | bash

# Global installation (~/.claude/settings.json)
curl -fsSL https://raw.githubusercontent.com/wangbooth/claude-code-guardrails/main/install.sh | bash -s -- --global

# Manual installation (copy .claude/ directory)
cp -r .claude/ /path/to/your-project/
chmod +x /path/to/your-project/.claude/hooks/*.sh
```

### Uninstallation
```bash
# Project-level uninstall
curl -fsSL https://raw.githubusercontent.com/wangbooth/claude-code-guardrails/main/uninstall.sh | bash

# Keep scripts, only remove from settings.json
curl -fsSL https://raw.githubusercontent.com/wangbooth/claude-code-guardrails/main/uninstall.sh | bash -s -- --keep-scripts

# Global uninstall
curl -fsSL https://raw.githubusercontent.com/wangbooth/claude-code-guardrails/main/uninstall.sh | bash -s -- --global
```

### Testing and Linting
```bash
# Run shellcheck on all scripts
shellcheck .claude/hooks/*.sh install.sh

# Run CI smoke test locally (requires Docker or Ubuntu environment)
# Creates temp repo and tests branch protection + commit functionality
bash .github/workflows/ci.yml  # Manual execution of CI steps
```

## Branch Protection Strategy

Protected branches (configurable in `guard-branch.sh`):
- `main`, `master`, `dev`
- Any branch matching `release*` pattern

When attempting to write to protected branches, the system:
1. Blocks the operation with exit code 2
2. Suggests creating a feature branch: `git checkout -b feat/$(date +%Y%m%d)-claude`
3. Allows Claude Code to see the suggestion and potentially adjust workflow

## Commit Workflow

### Checkpoint Phase
- Each Write/Edit/MultiEdit creates a checkpoint: `checkpoint: Write filename.ext - HH:MM`
- Only stages the specific files being modified (uses `git add -A -- "$file"`)
- Skips commits if no changes are staged

### Squash Phase (Stop/PreCompact)
- Consolidates multiple checkpoints into: `task: modified files - YYYY-MM-DD`
- Only operates on non-protected branches to avoid rewriting public history
- Requires local-only commits or ahead-of-upstream status to prevent conflicts
- Preserves last 3 checkpoint descriptions in final commit message

## Dependencies

- **Git** - Repository operations and commit management
- **jq** - JSON parsing for Claude Code hook payloads and settings merging
- **bash** - POSIX shell scripting environment

Install jq:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install -y jq
```

## Safety Features

- **Backup Creation**: All settings.json modifications create timestamped backups
- **Idempotent Installation**: Multiple installs won't duplicate hooks
- **History Preservation**: Protected branches never have history rewritten
- **Upstream Awareness**: Only squashes local-only or ahead commits
- **Precise Staging**: Only stages files actually being modified by Claude

## Customization

### Branch Protection Patterns
Modify the regex in `guard-branch.sh:8`:
```bash
protected='^(main|master|dev|release($|[/-].*))$'
```

### Commit Message Format
Customize checkpoint format in `auto-commit.sh:23`:
```bash
git commit -m "checkpoint: ${tool} ${changed:-$file} - ${now}"
```

### Timeout Configuration
Adjust hook timeouts in `claude/settings.json`:
- Branch guard: 10 seconds
- Auto-commit: 30 seconds
- Squash: 30-60 seconds
#!/bin/bash
# Custom Claude Code Status Line
# ================================
# Claude Code pipes a JSON blob to this script via stdin.
# Whatever we print to stdout becomes the status bar.
# Each echo/printf = one line in the status area.
#
# Available JSON fields (key ones):
#   .model.display_name        — "Opus", "Sonnet", "Haiku"
#   .model.id                  — "claude-opus-4-6", etc.
#   .context_window.used_percentage    — how full the context window is
#   .context_window.context_window_size — max tokens (200k or 1M)
#   .cost.total_cost_usd       — session cost so far
#   .cost.total_duration_ms    — session wall-clock time
#   .workspace.current_dir     — current working directory
#   .vim.mode                  — "NORMAL" or "INSERT" (absent if vim disabled)

# ── Read the JSON blob from stdin ──────────────────────────────
input=$(cat)

# ── Parse fields with jq ──────────────────────────────────────
# The "// value" syntax in jq provides a fallback if the field is null
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
MODEL_ID=$(echo "$input" | jq -r '.model.id // ""')
CTX_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
CUR_DIR=$(echo "$input" | jq -r '.workspace.current_dir // "~"')
VIM_MODE=$(echo "$input" | jq -r '.vim.mode // empty' 2>/dev/null)
LINES_ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# ── Derive model version string ───────────────────────────────
# Turn "Opus" into "Opus 4.6", etc. for a nicer display
case "$MODEL_ID" in
  *opus-4-6*)   MODEL_VER="Opus 4.6" ;;
  *sonnet-4-6*) MODEL_VER="Sonnet 4.6" ;;
  *haiku-4-5*)  MODEL_VER="Haiku 4.5" ;;
  *)            MODEL_VER="$MODEL" ;;
esac

# ── Context window label ──────────────────────────────────────
if [ "$CTX_SIZE" -ge 1000000 ] 2>/dev/null; then
  CTX_LABEL="1M"
else
  CTX_LABEL="200k"
fi

# ── Get project name + git branch ─────────────────────────────
PROJECT=$(basename "$CUR_DIR")

# Fast git branch detection (< 5ms typically)
GIT_BRANCH=""
GIT_DIRTY=""
if git -C "$CUR_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
  GIT_BRANCH=$(git -C "$CUR_DIR" symbolic-ref --short HEAD 2>/dev/null || \
               git -C "$CUR_DIR" rev-parse --short HEAD 2>/dev/null)
  # Check for uncommitted changes (the * in "main*")
  if ! git -C "$CUR_DIR" diff --quiet HEAD 2>/dev/null || \
     [ -n "$(git -C "$CUR_DIR" ls-files --others --exclude-standard 2>/dev/null | head -1)" ]; then
    GIT_DIRTY="*"
  fi
fi

# ── Build the dot/circle progress bar ─────────────────────────
# This is the visual meter: ● ● ● ● ○ ○ ○ ○ ○ ○
# 10 positions, filled proportionally to the percentage
build_dots() {
  local pct=${1:-0}
  local total=10
  local filled=$(( (pct * total + 50) / 100 ))  # round to nearest
  [ "$filled" -gt "$total" ] && filled=$total
  [ "$filled" -lt 0 ] && filled=0
  local empty=$((total - filled))

  local bar=""
  for ((i=0; i<filled; i++)); do bar+="● "; done
  for ((i=0; i<empty; i++)); do bar+="○ "; done
  echo "$bar"
}

# ── Format duration from milliseconds ─────────────────────────
format_duration() {
  local ms=${1:-0}
  local total_secs=$((ms / 1000))
  local hrs=$((total_secs / 3600))
  local mins=$(( (total_secs % 3600) / 60 ))

  if [ "$hrs" -gt 0 ]; then
    echo "${hrs}hr ${mins}min"
  elif [ "$mins" -gt 0 ]; then
    echo "${mins}min"
  else
    echo "${total_secs}s"
  fi
}

# ── Weekly usage tracking ─────────────────────────────────────
# Persists cumulative cost to a file, resets every Monday
# This lets us show a "weekly" usage bar across sessions
WEEKLY_FILE="$HOME/.claude/statusline-weekly.json"
SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"')

# Determine current week number and the next reset day
CURRENT_WEEK=$(date +%G-W%V)
# Find next Friday 10:00am as the reset point (adjust to your preference)
NEXT_FRIDAY=$(date -d "next friday 10:00" +"%a %I:%M%p" 2>/dev/null || echo "Fri")

update_weekly() {
  local current_cost="$1"
  local week="$2"

  # Initialize or read the weekly file
  if [ -f "$WEEKLY_FILE" ]; then
    local stored_week=$(jq -r '.week // ""' "$WEEKLY_FILE" 2>/dev/null)
    if [ "$stored_week" != "$week" ]; then
      # New week — reset
      echo "{\"week\":\"$week\",\"sessions\":{\"$SESSION_ID\":$current_cost}}" > "$WEEKLY_FILE"
    else
      # Same week — update this session's contribution
      jq --arg sid "$SESSION_ID" --argjson cost "$current_cost" \
        '.sessions[$sid] = $cost' "$WEEKLY_FILE" > "${WEEKLY_FILE}.tmp" && \
        mv "${WEEKLY_FILE}.tmp" "$WEEKLY_FILE"
    fi
  else
    echo "{\"week\":\"$week\",\"sessions\":{\"$SESSION_ID\":$current_cost}}" > "$WEEKLY_FILE"
  fi

  # Sum all session costs this week
  jq '[.sessions | to_entries[].value] | add // 0' "$WEEKLY_FILE" 2>/dev/null
}

WEEKLY_COST=$(update_weekly "$COST" "$CURRENT_WEEK")

# ── Calculate usage percentages ───────────────────────────────
# "current" = context window usage (how full is your conversation)
# "weekly"  = weekly spend as % of a budget (set your weekly budget below)
WEEKLY_BUDGET=50.00  # <── adjust: your weekly $ budget for Claude usage

# Weekly percentage (capped at 100)
# Use awk for reliable floating-point math (multiply first, then divide)
WEEKLY_PCT=$(awk "BEGIN { printf \"%d\", ($WEEKLY_COST * 100) / $WEEKLY_BUDGET }")
[ "$WEEKLY_PCT" -gt 100 ] 2>/dev/null && WEEKLY_PCT=100
[ -z "$WEEKLY_PCT" ] && WEEKLY_PCT=0

# ── ANSI color codes ──────────────────────────────────────────
# These make the output colorful in terminals that support it
RESET='\033[0m'
DIM='\033[2m'
BOLD='\033[1m'
CYAN='\033[36m'
YELLOW='\033[33m'
GREEN='\033[32m'
RED='\033[31m'
WHITE='\033[97m'
MAGENTA='\033[35m'

# Color the context % based on how full it is
if [ "$CTX_PCT" -ge 80 ]; then
  CTX_COLOR="$RED"
elif [ "$CTX_PCT" -ge 50 ]; then
  CTX_COLOR="$YELLOW"
else
  CTX_COLOR="$GREEN"
fi

# ── Build the output lines ────────────────────────────────────

# Line 1: Model │ ctx % │ project (branch*)
BRANCH_STR=""
if [ -n "$GIT_BRANCH" ]; then
  BRANCH_STR=" ${DIM}(${GIT_BRANCH}${GIT_DIRTY})${RESET}"
fi

printf "${BOLD}${CYAN}%s${RESET} ${DIM}│${RESET} ${CTX_COLOR}ctx %s%%${RESET} ${DIM}[%s]${RESET} ${DIM}│${RESET} ${WHITE}%s${RESET}%b${DIM} │${RESET} ${GREEN}+%s${RESET}/${RED}-%s${RESET}\n" \
  "$MODEL_VER" "$CTX_PCT" "$CTX_LABEL" "$PROJECT" "$BRANCH_STR" "$LINES_ADDED" "$LINES_REMOVED"

# Line 2: current session — context usage dots + duration
DURATION_STR=$(format_duration "$DURATION_MS")
CTX_DOTS=$(build_dots "$CTX_PCT")
printf "${DIM}current${RESET} %s ${BOLD}%s%%${RESET} ${DIM}↻${RESET} %s\n" \
  "$CTX_DOTS" "$CTX_PCT" "$DURATION_STR"

# Line 3 (disabled): weekly usage — cost dots + reset time
# WEEKLY_DOTS=$(build_dots "$WEEKLY_PCT")
# COST_FMT=$(printf '$%.2f' "$WEEKLY_COST")
# printf "${DIM}weekly ${RESET} %s ${BOLD}%s%%${RESET} ${DIM}↻${RESET} %s ${DIM}(%s/%s)${RESET}\n" \
#   "$WEEKLY_DOTS" "$WEEKLY_PCT" "$NEXT_FRIDAY" "$COST_FMT" "$(printf '$%.0f' "$WEEKLY_BUDGET")"

# Line 4 (disabled): Vim mode indicator (only if vim mode is enabled)
# if [ -n "$VIM_MODE" ]; then
#   if [ "$VIM_MODE" = "INSERT" ]; then
#     printf "${BOLD}${GREEN}-- INSERT --${RESET}\n"
#   else
#     printf "${DIM}-- NORMAL --${RESET}\n"
#   fi
# fi

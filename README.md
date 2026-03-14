# claude-statusline

A custom status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays model info, context usage, session duration, weekly cost tracking, and vim mode — all in a compact, colorful bar.

```
Opus 4.6 │ ctx 44% [1M] │ myproject (main*) │ +156/-23
current ● ● ● ● ○ ○ ○ ○ ○ ○  44% ↻ 2hr 14min
weekly  ● ● ● ○ ○ ○ ○ ○ ○ ○  26% ↻ Fri 10:00AM ($13/$50)
-- INSERT --
```

## Features

- **Model & context** — shows active model (Opus/Sonnet/Haiku), context window usage %, and window size (200k/1M)
- **Git info** — project name with branch and dirty indicator (`main*`)
- **Lines changed** — `+added/-removed` for the current session
- **Session meter** — dot progress bar for context usage with session duration
- **Weekly cost tracking** — cumulative cost across sessions, resets weekly, shown against a configurable budget
- **Vim mode** — INSERT/NORMAL indicator (only appears if vim mode is enabled)
- **Color-coded context** — green (<50%), yellow (50-80%), red (>80%)

## Requirements

- `bash`
- `jq` — for JSON parsing
- `git` — for branch detection (optional, gracefully skipped)

## Install

1. Copy the script somewhere convenient:

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

2. Update `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 1
  }
}
```

3. Restart Claude Code — the status line appears at the bottom.

## Configuration

Edit `statusline.sh` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `WEEKLY_BUDGET` | `50.00` | Your weekly $ budget — the weekly bar fills against this |
| Reset day | Friday | Change the `date -d "next friday"` line to your preferred reset day |
| Dot count | 10 | Adjust `total=10` in `build_dots()` for wider/narrower bars |

Weekly cost data is persisted to `~/.claude/statusline-weekly.json` and resets automatically each ISO week.

## How it works

Claude Code pipes a JSON blob to the script via stdin on each render cycle. The script:

1. Parses the JSON with `jq` to extract model, context, cost, and duration
2. Runs a fast `git` check for branch name and dirty state
3. Updates a weekly cost accumulator file (keyed by ISO week + session ID)
4. Outputs formatted lines with ANSI colors to stdout

Each line of stdout becomes a row in the Claude Code status bar.

## License

MIT

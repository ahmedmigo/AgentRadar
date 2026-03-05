# AgentRadar

A native macOS menu bar app that monitors AI coding agents running in your terminals — Claude Code, Gemini CLI, Codex CLI, Aider, and more.

## What it does

- **Lives in your menu bar** — icon changes based on agent status: working, completed, needs attention, or idle
- **Auto-detects agents** — scans running processes every 2 seconds for known AI coding agents
- **Shows live status** — CPU, memory, uptime, working directory, and current activity per agent
- **Claude Code deep integration** — reads JSONL transcripts for accurate status (thinking, tool approval, task completed)
- **Tool approval details** — shows which tool is waiting for approval and the command/file involved
- **Native notifications** — alerts you when an agent needs your attention
- **Click to focus** — click any agent row to activate its terminal window

## Detected Agents

| Agent | Binary | Detection |
|-------|--------|-----------|
| Claude Code | `claude` | `pgrep -x` + JSONL transcripts |
| Gemini CLI | `gemini` | `pgrep -f bin/gemini` |
| Codex CLI | `codex` | `pgrep -x` / `pgrep -f bin/codex` |
| Aider | `aider` | `pgrep -x` |
| Continue | `continue` | `pgrep -x` |
| OpenCode | `opencode` | `pgrep -x` |

To add more: edit `KnownAgent.all` in `AgentMonitor.swift`.

## Menu Bar Icons

| Icon | Meaning |
|------|---------|
| `dot.radiowaves.left.and.right` | Agent actively working |
| `checkmark.circle` | All agents completed their tasks |
| `N.circle.fill` (orange) | N agents need your attention |
| `dot.radiowaves.left.and.right` (dimmed) | Agents idle |
| `circle.dotted` | No agents running |

## Setup

### Requirements
- macOS 13.0+
- Xcode 15+

### Build & Run

```bash
xcodebuild -project AgentRadar.xcodeproj \
           -scheme AgentRadar \
           -configuration Release \
           -derivedDataPath build

open build/Build/Products/Release/AgentRadar.app
```

### Auto-launch on login
1. Open **System Settings > General > Login Items**
2. Click **+** and add `AgentRadar.app`

## Privacy

AgentRadar reads the process list (`ps`, `pgrep`), working directories (`lsof`), and Claude Code JSONL transcripts for status detection. It never reads terminal output or network traffic. No data leaves your machine.

## Architecture

```
AgentRadarApp.swift    — App entry point (@main)
AppDelegate.swift      — NSStatusItem, popover lifecycle, notifications
AgentMonitor.swift     — Process scanning, agent model, status detection
PopoverView.swift      — SwiftUI popover UI
Info.plist             — LSUIElement=true hides dock icon
```

## Author

[ahmedmigo](https://github.com/ahmedmigo)

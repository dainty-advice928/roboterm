# ROBOTERM — Project Context

## What
ROS2-native agentic terminal for Apple Silicon. Thin Swift shell over SwiftTerm (pure-Swift terminal emulator).

## Repo
- **GitHub**: https://github.com/RobotFlow-Labs/roboterm
- **Local**: This directory

## Build
```bash
./scripts/build.sh --install --run
# or manually:
xcodegen generate
xcodebuild -project roboterm.xcodeproj -scheme roboterm -configuration Debug build
```

## Architecture
- `Sources/` — All Swift code (~6500 lines, 24 files)
- `Sources/AppleScript/` — Cocoa scripting support (SDEF + wrappers)
- `Resources/Roboterm.sdef` — AppleScript dictionary
- `scripts/roboterm-tools.sh` — 31 shell commands (1100+ lines)
- `project.yml` — xcodegen config (auto-generates .xcodeproj)

## Key Files
| File | Purpose |
|------|---------|
| `RobotermApp.swift` | App entry point (@main) |
| `AppDelegate.swift` | Window management, menu actions, session mgmt |
| `AppDelegate+Menu.swift` | Main menu construction (60+ commands) |
| `ContentView.swift` | Sidebar + tab bar + terminal layout |
| `TabManager.swift` | Workspace/tab management, SSH tab creation |
| `Tab.swift` | Tab model with SSH support (`sshConfig`, `isSSH`) |
| `TerminalView.swift` | RobotermTerminal (SwiftTerm LocalProcessTerminalView) |
| `Workspace.swift` | Tab grouping, ROS2 workspace detection |
| `SessionStore.swift` | Save/restore state to JSON (incl. SSH tabs) |
| `TerminalSettings.swift` | Settings singleton, agent/ANIMA/SSH config models |
| `PreferencesView.swift` | 5-tab preferences (General, Appearance, Agents, ANIMA, SSH) |
| `AgentBar.swift` | Claude/Codex launcher + ROS2 quick buttons |
| `StatusBar.swift` | Bottom bar: CPU/MEM/git/ROS2/clock (SSH-aware) |
| `AnimaPanel.swift` | ANIMA modules sidebar panel + Docker status polling |
| `SSHPanel.swift` | SSH connections sidebar panel (one-click connect) |
| `DockerPanel.swift` | Docker compose groups sidebar panel |
| `HardwarePanel.swift` | Hardware auto-detection (IOKit + network hosts) |
| `DesignTokens.swift` | RF namespace (colors, fonts, spacing) |
| `SplitContainerView.swift` | Terminal split view management |
| `SplitNode.swift` | Split tree data structure |

## Config Files (runtime)
| Path | Content |
|------|---------|
| `~/.config/roboterm/agents.json` | Agent configs (Claude, Codex, custom) |
| `~/.config/roboterm/anima.json` | ANIMA module configs |
| `~/.config/roboterm/ssh-connections.json` | SSH connection profiles |
| `~/.config/roboterm/sessions.json` | Auto-saved session state |
| `~/.config/roboterm/sessions/` | Named session profiles |

## SSH Support (v0.5.0)
- **Direct process**: SSH tabs start `/usr/bin/ssh` as PTY process (no shell + sendText hack)
- **SSH connections**: `SSHConnectionConfig` model stored in `ssh-connections.json`
- **Sidebar panel**: "SSH CONNECTIONS" with one-click connect
- **Tab differentiation**: SSH tabs show network icon + cyan accent + `[SSH]` title prefix
- **Preferences tab**: Full SSH connection CRUD with Browse for key files
- **Session persistence**: SSH tabs restore on relaunch
- **Smart integration**: SSH tabs skip directory regrouping, skip ROS2 env, status bar shows `[SSH] user@host`

## Design System (RF namespace)
| Token | Value | Use |
|-------|-------|-----|
| `RF.accent` | `#FF3B00` | Orange — primary accent, selected indicators |
| `RF.green` | `#00FF88` | Running status, ROS2 |
| `RF.cyan` | `#00DDFF` | SSH connections, network |
| `RF.purple` | `#8B5CFF` | GPU profiles |
| `RF.yellow` | `#FFB800` | Warnings, tools |
| `RF.voidBlack` | `#050505` | Main background |
| `RF.sidebarBg` | `#080808` | Sidebar background |
| `RF.barBg` | `#0A0A0A` | Agent/status bar background |

## Conventions
- Use `rg` instead of `grep`
- No rounded corners in UI (Industrial Cyberpunk)
- Monospaced fonts everywhere (Oswald for display, JetBrains Mono for body)
- All uppercase labels with letter-spacing in sidebar
- SwiftTerm as terminal backend (not Ghostty)
- `project.yml` + xcodegen — never edit `.xcodeproj` directly

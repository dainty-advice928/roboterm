# ROBOTERM v0.2.0 Roadmap

Based on deep research (March 18, 2026) + v0.1.0 learnings.

## What's Shipped (v0.1.0) — 29 commits, 4610 lines Swift
- Agent bar (Claude + Codex)
- 60+ ROS2 menu commands
- 25 `rt` CLI commands
- IOKit USB hotplug monitor
- AppleScript (SDEF + Cocoa scripting)
- Session persistence
- Status bar (CPU/MEM/git/ROS2/clock)
- Industrial Cyberpunk design
- Right-click context menu
- ROS2 workspace auto-detection
- Environment profiles, Foxglove export, custom aliases

---

## v0.2.0 — Research-Driven Features

### P0: Fix IOKit USB from .app bundle
**Problem**: IOKit enumeration works from CLI but returns empty from packaged .app.
**Research finding**: Use `IOUSBHostDevice` (not `IOUSBDevice`). The hotplug monitor code is correct but the initial `enumerateUSBDevices()` may fail because `kIOMasterPortDefault` is deprecated — use `kIOMainPortDefault`.
**Fix**: Already using `kIOMainPortDefault`. The issue may be code signing — test with `codesign --entitlements` adding `com.apple.security.device.usb`.
**Estimate**: 1 hour

### P0: Fix SwiftUI layout for status/agent bars
**Problem**: NSViewRepresentable terminal view expands over SwiftUI bars.
**Research finding**: Use `autoresizingMask = [.width, .height]` instead of Auto Layout constraints. Implement `sizeThatFits(_:nsView:context:)` on the representable (macOS 13+).
**Code from research**:
```swift
override func layout() {
    super.layout()
    terminalView.frame = bounds
}
```
**Estimate**: 2 hours

### P1: CLI Inspector Panel
**Research finding**: Parse `ros2 <command> -h` at runtime to always show correct flags for installed distro. No hardcoded flag matrix needed.
**Implementation**:
- `rt inspect <command> [verb]` — show all flags with descriptions
- Parse argparse output into structured data
- Cache results per distro version
**Estimate**: 3 hours

### P1: Ghostty Theme Picker
**Research finding**: `ghostty +list-themes` shows all available themes. `ghostty +show-config --default --docs` dumps every option.
**Implementation**:
- Menu item: Robotics → Appearance → Theme Picker
- Run `ghostty +list-themes --path` to list themes
- Apply by writing to `~/.config/ghostty/config`
- Live preview via `ghostty_config_load_file` + `ghostty_app_update_config`
**Estimate**: 2 hours

### P1: Ghostty Config Generator
**Research finding**: Full config reference from `ghostty +show-config --default --docs`.
**Implementation**:
- `rt config` — interactive config editor
- `rt config show` — dump current config
- `rt config set <key> <value>` — set a config value
- `rt config reset` — restore default Industrial Cyberpunk theme
**Estimate**: 2 hours

### P2: Native ROS2 Integration (RosSwift)
**Research finding**: RosSwift (tgu/RosSwift) provides pure Swift ROS2 pub/sub via SwiftNIO.
**Implementation**:
- Add RosSwift as SPM dependency
- `rt subscribe <topic>` — native subscription without spawning ros2 CLI
- Real-time topic monitor in status bar
- Agent-as-ROS2-node pattern (per ANIMA architecture)
**Estimate**: 1 day

### P2: ros2tui Integration
**Research finding**: `ros2tui` (uupks/ros2tui) is an existing terminal UI for ROS2 using ftxui.
**Implementation**:
- Evaluate as optional integration
- If useful, add as Robotics menu item: "ROS2 TUI Dashboard"
**Estimate**: 2 hours

### P2: Better Network Reachability
**Research finding**: Use `NWConnection` TCP probe (already done) + `SCNetworkReachability` for route-level checks.
**Implementation**:
- Already using NWConnection for host probes
- Add SCNetworkReachability for fast "network available" check
- Show network status in status bar
**Estimate**: 1 hour

### P3: Bag Timeline Viewer
**Implementation**:
- `rt bag timeline <bag>` — ASCII timeline of topics in a bag
- Show when each topic was active, message counts per second
- Export timeline as CSV for Foxglove
**Estimate**: 3 hours

### P3: Recording Indicator
**Implementation**:
- Detect `ros2 bag record` running (check process list)
- Show red REC indicator in status bar with duration
- Click to stop recording
**Estimate**: 2 hours

### P3: Inline Camera Preview
**Research finding**: Ghostty supports Kitty graphics protocol for inline images.
**Implementation**:
- `rt camera preview <topic>` — show latest camera frame inline
- Use `ros2 topic echo --once` + decode image
- Display via Kitty graphics protocol or save to /tmp and show path
**Estimate**: 4 hours

---

## Architecture Improvements (from research)

### Modularize into Frameworks
Split Sources/ into separate modules for faster incremental builds:
- `RobotermCore/` — TabManager, Workspace, SessionStore
- `RobotermUI/` — ContentView, AgentBar, StatusBar
- `RobotermHardware/` — HardwarePanel, USBHotplugMonitor
- `RobotermROS/` — ROS2 integration, CLI tools
- `RobotermAppleScript/` — Cocoa scripting

### Swift Subprocess (Official)
Replace all `Process` calls with `swift-subprocess` (shipped Sep 2025).
Async/await, proper timeout management, output streaming.

### Shell Integration
Surface Ghostty's `shell-integration-features` in ROBOTERM preferences.
Especially important: `ssh-env` and `ssh-terminfo` for robot SSH sessions.

---

## Timeline

| Week | Focus | Features |
|------|-------|----------|
| 1 | Fixes | IOKit USB fix, SwiftUI layout fix |
| 2 | DX | CLI Inspector, Ghostty theme picker, config generator |
| 3 | Native | RosSwift integration, ros2tui |
| 4 | Polish | Bag timeline, recording indicator, camera preview |

---

## Key Research Sources
- Ghostty config: https://ghostty.org/docs/config/reference
- IOKit USB: IOUSBHostDevice class, IOServiceAddMatchingNotification
- ROS2 CLI: https://github.com/ros2/ros2cli (parse -h at runtime)
- SwiftUI+AppKit: sizeThatFits, autoresizingMask pattern
- RosSwift: https://github.com/tgu/RosSwift
- ros2tui: https://github.com/uupks/ros2tui
- Network: NWConnection TCP probe + SCNetworkReachability

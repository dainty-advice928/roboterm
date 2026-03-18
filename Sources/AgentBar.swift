import SwiftUI

// MARK: - Agent definitions

struct AgentDef {
    let name: String
    let icon: String
    let command: String
    let color: Color
}

private let agents: [AgentDef] = [
    AgentDef(name: "claude", icon: "\u{2728}", command: "claude", color: Color(red: 0xFF/255, green: 0x3B/255, blue: 0x00/255)),
    AgentDef(name: "codex", icon: "\u{2699}", command: "codex", color: Color(red: 0x00/255, green: 0xFF/255, blue: 0x88/255)),
]

private let rfAccent = Color(red: 0xFF/255, green: 0x3B/255, blue: 0x00/255)
private let rfGreen  = Color(red: 0x00/255, green: 0xFF/255, blue: 0x88/255)
private let rfCyan   = Color(red: 0x00/255, green: 0xDD/255, blue: 0xFF/255)
private let rfPurple = Color(red: 0x8B/255, green: 0x5C/255, blue: 0xFF/255)
private let rfYellow = Color(red: 0xFF/255, green: 0xB8/255, blue: 0x00/255)

// MARK: - Agent Launcher Bar

struct AgentBar: View {
    @ObservedObject var tabManager: TabManager

    private let barBg = Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255)
    private let borderColor = Color(red: 0xFF/255, green: 0x3B/255, blue: 0x00/255).opacity(0.15)

    var body: some View {
        HStack(spacing: 0) {
            // Agent buttons
            ForEach(agents, id: \.name) { agent in
                BarButton(label: agent.name, dotColor: agent.color) {
                    launchAgent(agent)
                }
            }

            // Separator
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 14)
                .padding(.horizontal, 2)

            // ROS2 quick-launch tools
            BarButton(label: "nodes", dotColor: rfGreen) { launchCommand("ros2 node list") }
            BarButton(label: "topics", dotColor: rfGreen) { launchCommand("ros2 topic list -v") }
            BarButton(label: "services", dotColor: rfGreen) { launchCommand("ros2 service list") }
            BarButton(label: "params", dotColor: rfGreen) { launchCommand("ros2 param list") }

            // Separator
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 14)
                .padding(.horizontal, 2)

            // Sim & tools
            BarButton(label: "gazebo", dotColor: rfCyan) { launchCommand("gz sim") }
            BarButton(label: "rviz2", dotColor: rfPurple) { launchCommand("rviz2") }
            BarButton(label: "rqt", dotColor: rfYellow) { launchCommand("rqt") }

            Spacer()

            // Right side
            BarButton(label: "doctor", dotColor: rfYellow) { launchCommand("ros2 doctor --report") }
            BarButton(label: "docker", dotColor: rfCyan) { launchCommand("docker compose ps") }
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(barBg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(borderColor).frame(height: 1)
        }
    }

    private func launchAgent(_ agent: AgentDef) {
        launchCommand(agent.command)
    }

    private func launchCommand(_ command: String) {
        // TUI/long-running commands open in a new tab, quick commands run in current tab
        let tuiCommands = ["claude", "codex", "rviz2", "rqt", "rqt_graph", "gz sim",
                           "python3 -m mujoco.viewer", "isaac-sim"]
        let openInNewTab = tuiCommands.contains(where: { command.hasPrefix($0) })

        if openInNewTab {
            guard let ws = tabManager.selectedWorkspace else { return }
            let tab = ws.createTab()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let surface = tab.terminalView?.surface {
                    let cmd = command + "\n"
                    cmd.withCString { ptr in
                        ghostty_surface_text(surface, ptr, UInt(cmd.utf8.count))
                    }
                }
            }
        } else {
            // Run in current tab
            guard let tab = tabManager.selectedTab,
                  let surface = tab.terminalView?.surface else { return }
            let cmd = command + "\n"
            cmd.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(cmd.utf8.count))
            }
        }
    }
}

// MARK: - Unified bar button (all buttons same style)

struct BarButton: View {
    let label: String
    let dotColor: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isHovering ? dotColor : dotColor.opacity(0.4))
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundColor(isHovering ? dotColor : .white.opacity(0.4))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Rectangle()
                    .fill(isHovering ? dotColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

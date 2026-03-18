import AppKit
import SwiftUI

// MARK: - Docker container model

struct DockerContainer: Identifiable {
    let id: String
    let name: String
    let image: String
    let status: ContainerStatus
    let ports: String
    let created: String

    enum ContainerStatus {
        case running, stopped, paused

        var label: String {
            switch self {
            case .running: return "RUNNING"
            case .stopped: return "STOPPED"
            case .paused:  return "PAUSED"
            }
        }
    }
}

// MARK: - Docker state (singleton)

@MainActor
final class DockerState: ObservableObject {
    static let shared = DockerState()

    @Published var containers: [DockerContainer] = []
    @Published var isLoading = false

    private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.listContainers()
            DispatchQueue.main.async {
                self?.containers = result
                self?.isLoading = false
            }
        }
    }

    func startContainer(_ id: String) {
        runDockerCmd("docker start \(id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    func stopContainer(_ id: String) {
        runDockerCmd("docker stop \(id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    func restartContainer(_ id: String) {
        runDockerCmd("docker restart \(id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refresh() }
    }

    func removeContainer(_ id: String) {
        runDockerCmd("docker rm -f \(id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    private func runDockerCmd(_ command: String) {
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", "export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH && " + command]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    private static func listContainers() -> [DockerContainer] {
        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH && docker ps -a --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}|{{.CreatedAt}}' 2>/dev/null"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4 else { return nil }

            let statusStr = parts[3].lowercased()
            let status: DockerContainer.ContainerStatus =
                statusStr.contains("up") ? .running :
                statusStr.contains("paused") ? .paused : .stopped

            return DockerContainer(
                id: parts[0],
                name: parts[1],
                image: parts.count > 2 ? parts[2] : "",
                status: status,
                ports: parts.count > 4 ? parts[4] : "",
                created: parts.count > 5 ? parts[5] : ""
            )
        }
    }
}

// MARK: - Design tokens

private let dpAccent  = Color(red: 0xFF/255, green: 0x3B/255, blue: 0x00/255)
private let dpGreen   = Color(red: 0x00/255, green: 0xFF/255, blue: 0x88/255)
private let dpCyan    = Color(red: 0x00/255, green: 0xDD/255, blue: 0xFF/255)
private let dpYellow  = Color(red: 0xFF/255, green: 0xB8/255, blue: 0x00/255)
private let dpDim     = Color.white.opacity(0.3)
private let dpBg      = Color(red: 0x08/255, green: 0x08/255, blue: 0x08/255)

// MARK: - Docker Panel View

struct DockerPanelView: View {
    @ObservedObject private var state = DockerState.shared
    @ObservedObject var tabManager: TabManager

    private var runningCount: Int {
        state.containers.filter { $0.status == .running }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DockerPanelHeader(
                runningCount: runningCount,
                totalCount: state.containers.count,
                onRefresh: { state.refresh() }
            )

            Rectangle().fill(dpCyan.opacity(0.15)).frame(height: 1)
                .padding(.horizontal, 8)

            if state.containers.isEmpty {
                DockerEmptyState()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(state.containers) { container in
                            DockerContainerRow(
                                container: container,
                                onShell: { openShell(container) },
                                onLogs: { openLogs(container) },
                                onStart: { state.startContainer(container.id) },
                                onStop: { state.stopContainer(container.id) },
                                onRestart: { state.restartContainer(container.id) },
                                onRemove: { state.removeContainer(container.id) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
    }

    // MARK: - Actions

    private func openShell(_ container: DockerContainer) {
        guard let ws = tabManager.selectedWorkspace else { return }
        let tab = ws.createTab()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            tab.terminalView?.sendText("docker exec -it \(container.name) bash\n")
        }
    }

    private func openLogs(_ container: DockerContainer) {
        guard let ws = tabManager.selectedWorkspace else { return }
        let tab = ws.createTab()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            tab.terminalView?.sendText("docker logs -f --tail=100 \(container.name)\n")
        }
    }
}

// MARK: - Header

private struct DockerPanelHeader: View {
    let runningCount: Int
    let totalCount: Int
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("CONTAINERS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(dpCyan.opacity(0.8))
                .tracking(1.5)

            Spacer()

            // Running badge
            HStack(spacing: 3) {
                Circle().fill(runningCount > 0 ? dpGreen : dpDim).frame(width: 5, height: 5)
                Text("\(runningCount)/\(totalCount)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(runningCount > 0 ? dpGreen.opacity(0.7) : dpDim)
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9))
                    .foregroundStyle(dpDim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Empty state

private struct DockerEmptyState: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("NO CONTAINERS")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(dpDim)
            Text("docker compose up")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(dpCyan.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Container Row

private struct DockerContainerRow: View {
    let container: DockerContainer
    let onShell: () -> Void
    let onLogs: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    private var statusColor: Color {
        switch container.status {
        case .running: return dpGreen
        case .paused:  return dpYellow
        case .stopped: return dpDim
        }
    }

    private var shortImage: String {
        let img = container.image
        // Show last component: "robotflowlabs/roboros-demo:local" → "roboros-demo:local"
        if let last = img.split(separator: "/").last { return String(last) }
        return img
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle().fill(statusColor).frame(width: 6, height: 6)

            // Name + image
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isHovering ? dpCyan : .white.opacity(0.6))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(shortImage)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                        .lineLimit(1)

                    if !container.ports.isEmpty {
                        Text(container.ports)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(dpCyan.opacity(0.3))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Action buttons (visible on hover)
            if isHovering {
                ContainerActions(
                    status: container.status,
                    onShell: onShell,
                    onLogs: onLogs,
                    onStart: onStart,
                    onStop: onStop,
                    onRemove: onRemove
                )
            } else {
                // Status label
                Text(container.status.label)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor.opacity(0.5))
                    .tracking(0.5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? dpCyan.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            ContainerContextMenu(
                status: container.status,
                onShell: onShell,
                onLogs: onLogs,
                onStart: onStart,
                onStop: onStop,
                onRestart: onRestart,
                onRemove: onRemove
            )
        }
    }
}

// MARK: - Action Buttons

private struct ContainerActions: View {
    let status: DockerContainer.ContainerStatus
    let onShell: () -> Void
    let onLogs: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if status == .running {
                ActionButton(icon: "terminal", color: dpCyan, help: "Shell", action: onShell)
                ActionButton(icon: "doc.text", color: dpGreen, help: "Logs", action: onLogs)
                ActionButton(icon: "stop.fill", color: dpAccent, help: "Stop", action: onStop)
            } else {
                ActionButton(icon: "play.fill", color: dpGreen, help: "Start", action: onStart)
                ActionButton(icon: "trash", color: dpAccent.opacity(0.6), help: "Remove", action: onRemove)
            }
        }
    }
}

private struct ActionButton: View {
    let icon: String
    let color: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Context Menu

private struct ContainerContextMenu: View {
    let status: DockerContainer.ContainerStatus
    let onShell: () -> Void
    let onLogs: () -> Void
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if status == .running {
            Button("Open Shell", action: onShell)
            Button("View Logs", action: onLogs)
            Divider()
            Button("Restart", action: onRestart)
            Button("Stop", action: onStop)
        } else {
            Button("Start", action: onStart)
            Divider()
            Button("Remove", action: onRemove)
        }
    }
}

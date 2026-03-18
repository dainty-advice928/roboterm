import AppKit
import SwiftUI

// MARK: - Docker container model

struct DockerContainer: Identifiable {
    let id: String          // container ID (short)
    let name: String
    let image: String
    let status: ContainerStatus
    let ports: String
    let created: String

    enum ContainerStatus {
        case running, stopped, paused
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
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
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
        runDockerCommand("docker start \(id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    func stopContainer(_ id: String) {
        runDockerCommand("docker stop \(id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    func restartContainer(_ id: String) {
        runDockerCommand("docker restart \(id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refresh() }
    }

    func removeContainer(_ id: String) {
        runDockerCommand("docker rm -f \(id)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    private func runDockerCommand(_ command: String) {
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", command]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
    }

    // MARK: - Parse docker ps output

    private static func listContainers() -> [DockerContainer] {
        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "docker ps -a --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}|{{.CreatedAt}}' 2>/dev/null"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 4 else { return nil }

            let statusStr = parts[3].lowercased()
            let status: DockerContainer.ContainerStatus
            if statusStr.contains("up") {
                status = .running
            } else if statusStr.contains("paused") {
                status = .paused
            } else {
                status = .stopped
            }

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

// MARK: - Docker Panel View (for Robotics menu or sidebar)

private let dpAccent = Color(red: 0xFF/255, green: 0x3B/255, blue: 0x00/255)
private let dpGreen  = Color(red: 0x00/255, green: 0xFF/255, blue: 0x88/255)
private let dpCyan   = Color(red: 0x00/255, green: 0xDD/255, blue: 0xFF/255)
private let dpDim    = Color.white.opacity(0.3)

struct DockerPanelView: View {
    @ObservedObject private var state = DockerState.shared
    @ObservedObject var tabManager: TabManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("CONTAINERS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(dpCyan.opacity(0.7))
                    .tracking(1.5)
                Spacer()
                Text("\(state.containers.filter { $0.status == .running }.count) running")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(dpDim)
                Button(action: { state.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8))
                        .foregroundColor(dpDim)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Rectangle().fill(dpCyan.opacity(0.15)).frame(height: 1)
                .padding(.horizontal, 8)

            // Container list
            if state.containers.isEmpty {
                Text("NO CONTAINERS")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(dpDim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(state.containers) { container in
                            DockerContainerRow(container: container, tabManager: tabManager)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }
}

// MARK: - Container Row

struct DockerContainerRow: View {
    let container: DockerContainer
    @ObservedObject var tabManager: TabManager
    @State private var isHovering = false

    private var statusColor: Color {
        switch container.status {
        case .running: return dpGreen
        case .paused: return Color(red: 0xFF/255, green: 0xB8/255, blue: 0x00/255)
        case .stopped: return dpDim
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(container.name.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isHovering ? dpCyan : .white.opacity(0.5))
                    .lineLimit(1)
                Text(container.image.components(separatedBy: "/").last ?? container.image)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .lineLimit(1)
            }

            Spacer()

            if isHovering {
                HStack(spacing: 4) {
                    if container.status == .running {
                        // Shell button
                        Button(action: { openShell(container) }) {
                            Image(systemName: "terminal")
                                .font(.system(size: 8))
                                .foregroundColor(dpCyan)
                        }
                        .buttonStyle(.plain)
                        .help("Open shell")

                        // Logs button
                        Button(action: { openLogs(container) }) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 8))
                                .foregroundColor(dpGreen)
                        }
                        .buttonStyle(.plain)
                        .help("View logs")

                        // Stop button
                        Button(action: { DockerState.shared.stopContainer(container.id) }) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 7))
                                .foregroundColor(dpAccent)
                        }
                        .buttonStyle(.plain)
                        .help("Stop")
                    } else {
                        // Start button
                        Button(action: { DockerState.shared.startContainer(container.id) }) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 7))
                                .foregroundColor(dpGreen)
                        }
                        .buttonStyle(.plain)
                        .help("Start")

                        // Remove button
                        Button(action: { DockerState.shared.removeContainer(container.id) }) {
                            Image(systemName: "trash")
                                .font(.system(size: 7))
                                .foregroundColor(dpAccent.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovering ? dpCyan.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if container.status == .running {
                Button("Open Shell") { openShell(container) }
                Button("View Logs") { openLogs(container) }
                Divider()
                Button("Restart") { DockerState.shared.restartContainer(container.id) }
                Button("Stop") { DockerState.shared.stopContainer(container.id) }
            } else {
                Button("Start") { DockerState.shared.startContainer(container.id) }
                Divider()
                Button("Remove") { DockerState.shared.removeContainer(container.id) }
            }
        }
    }

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
            tab.terminalView?.sendText("docker logs -f --tail=50 \(container.name)\n")
        }
    }
}

import AppKit
import SwiftUI

/// Bottom status bar — lightweight system info.
/// Updates on: tab switch, directory change, 10-second timer.
struct StatusBarView: View {
    @ObservedObject var tabManager: TabManager
    @State private var gitBranch: String = ""
    @State private var rosDistro: String = ""
    @State private var rosDomain: String = ""
    @State private var cpuUsage: String = ""
    @State private var memUsage: String = ""
    @State private var clock: String = ""
    @State private var cwd: String = "~"
    @State private var lastGitDir: String = ""
    @State private var prevCpuTicks: (user: UInt64, system: UInt64, idle: UInt64) = (0, 0, 0)

    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let clockFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    /// Whether the currently selected tab is an SSH connection.
    private var isSSHTab: Bool {
        tabManager.selectedTab?.isSSH ?? false
    }

    /// SSH connection label for the status bar.
    private var sshLabel: String {
        guard let ssh = tabManager.selectedTab?.sshConfig else { return "" }
        let userHost = ssh.user.isEmpty ? ssh.host : "\(ssh.user)@\(ssh.host)"
        return ssh.port != 22 ? "\(userHost):\(ssh.port)" : userHost
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSSHTab {
                // SSH tab: show connection info instead of local CWD/git
                Image(systemName: "network")
                    .font(.system(size: 9))
                    .foregroundColor(RF.cyan)
                    .padding(.trailing, 4)
                Text("SSH")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(RF.cyan)
                separatorView
                Text(sshLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(RF.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                // Left: ROS2 info
                if !rosDistro.isEmpty {
                    statusDot(color: RF.green)
                    statusLabel("ROS2:", value: rosDistro, valueColor: RF.green)
                    separatorView
                    statusLabel("DOMAIN:", value: rosDomain.isEmpty ? "0" : rosDomain, valueColor: RF.accent)
                    separatorView
                }

                // Git branch
                if !gitBranch.isEmpty {
                    Text("\u{2387}")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(RF.dim)
                    statusLabel("", value: gitBranch, valueColor: RF.accent)
                    separatorView
                }

                // CWD
                Text(cwd)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(RF.dim)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            // Right: system stats + clock
            statusLabel("CPU:", value: cpuUsage, valueColor: RF.accent)
            separatorView
            statusLabel("MEM:", value: memUsage, valueColor: RF.accent)
            separatorView
            Text(clock)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(RF.dim)
                .padding(.trailing, 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .frame(minHeight: 22, maxHeight: 22)
        .background(RF.barBg)
        .overlay(alignment: .top) {
            Rectangle().fill(RF.accent.opacity(0.3)).frame(height: 1)
        }
        .onAppear { refresh() }
        .onReceive(timer) { _ in refresh() }
        .onReceive(clockTimer) { _ in updateClock() }
        .onChange(of: tabManager.selectedWorkspaceId) { _ in lastGitDir = ""; refresh() }
        .onChange(of: tabManager.selectedWorkspace?.selectedTabId) { _ in lastGitDir = ""; refresh() }
    }

    // MARK: - Subviews

    private func statusDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .padding(.trailing, 4)
    }

    private func statusLabel(_ label: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 3) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(RF.dim)
            }
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(valueColor)
        }
    }

    private var separatorView: some View {
        Text("|")
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(Color.white.opacity(0.12))
            .padding(.horizontal, 6)
    }

    // MARK: - Data refresh

    private func refresh() {
        // Skip local-only updates for SSH tabs
        if !isSSHTab {
            updateCwd()
            updateGitBranch()
            updateROS2()
        }
        updateSystemStats()
    }

    private func updateCwd() {
        let dir = tabManager.selectedTab?.currentDirectory
            ?? tabManager.selectedWorkspace?.directory
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            let rel = String(dir.dropFirst(home.count))
            cwd = rel.isEmpty ? "~" : "~" + rel
        } else {
            cwd = dir
        }
    }

    private func updateGitBranch() {
        let dir = tabManager.selectedTab?.currentDirectory
            ?? tabManager.selectedWorkspace?.directory ?? ""
        // Skip if directory hasn't changed since last check
        if dir == lastGitDir { return }
        lastGitDir = dir
        // Walk up to find .git/HEAD
        var current = dir
        while !current.isEmpty && current != "/" {
            let headPath = current + "/.git/HEAD"
            if let content = try? String(contentsOfFile: headPath, encoding: .utf8) {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("ref: refs/heads/") {
                    gitBranch = String(trimmed.dropFirst("ref: refs/heads/".count))
                } else {
                    gitBranch = String(trimmed.prefix(8))
                }
                return
            }
            current = (current as NSString).deletingLastPathComponent
        }
        gitBranch = ""
    }

    private func updateROS2() {
        if let distro = ProcessInfo.processInfo.environment["ROS_DISTRO"] {
            rosDistro = distro
        } else {
            rosDistro = ""
        }
        rosDomain = ProcessInfo.processInfo.environment["ROS_DOMAIN_ID"] ?? ""
    }

    private func updateSystemStats() {
        // CPU via host_statistics — delta between readings for real-time usage
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()

        let result = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let curUser = UInt64(loadInfo.cpu_ticks.0)
            let curSystem = UInt64(loadInfo.cpu_ticks.1)
            let curIdle = UInt64(loadInfo.cpu_ticks.2)

            let prev = prevCpuTicks
            prevCpuTicks = (curUser, curSystem, curIdle)

            // First reading — no delta yet, show "—"
            guard prev.user > 0 || prev.system > 0 || prev.idle > 0 else {
                cpuUsage = "—"
                // fall through to memory
                updateMemory(host: host)
                return
            }

            let dUser = curUser - prev.user
            let dSystem = curSystem - prev.system
            let dIdle = curIdle - prev.idle
            let dTotal = dUser + dSystem + dIdle
            if dTotal > 0 {
                let usage = Double(dUser + dSystem) / Double(dTotal) * 100
                cpuUsage = String(format: "%.0f%%", usage)
            }
        } else {
            cpuUsage = "N/A"
        }

        updateMemory(host: host)
    }

    private func updateMemory(host: mach_port_t) {
        let totalMem = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalMem) / 1_073_741_824
        var vmStats = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let vmResult = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }

        if vmResult == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let active = UInt64(vmStats.active_count) * pageSize
            let wired = UInt64(vmStats.wire_count) * pageSize
            let compressed = UInt64(vmStats.compressor_page_count) * pageSize
            let usedGB = Double(active + wired + compressed) / 1_073_741_824
            memUsage = String(format: "%.0fGB/%.0fGB", usedGB, totalGB)
        } else {
            memUsage = "N/A"
        }
    }

    private func updateClock() {
        clock = Self.clockFormatter.string(from: Date())
    }
}

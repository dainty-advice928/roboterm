import AppKit
import Combine
import Foundation
import SwiftTerm

/// NSView that hosts a single terminal session using SwiftTerm's LocalProcessTerminalView.
///
/// All keyboard, mouse, scroll, and IME handling is provided automatically by SwiftTerm.
/// A private delegate bridge (TerminalProcessDelegate) captures process events and
/// forwards them as NotificationCenter posts so TabManager / Tab can react without
/// any direct reference to SwiftTerm types.
///
/// The public interface (tabId, surfaceId, sendText, workingDirectory) is used by
/// Tab, TabManager, SplitContainerView, and AppleScript callers.
class RobotermTerminal: LocalProcessTerminalView {

    // MARK: - Public interface (kept for caller compatibility)

    /// Stable identifier used by SplitContainerView lookups.
    let surfaceId: UUID

    /// The Tab that owns this view.
    let tabId: UUID

    /// Optional working directory to start the shell in.
    var workingDirectory: String?

    /// SSH connection config — when set, starts /usr/bin/ssh as the process instead of a shell.
    var sshConfig: SSHConnectionConfig?

    // MARK: - Private

    /// Dedicated delegate object so we don't fight with LocalProcessTerminalView's own
    /// method implementations (most are public, not open, so we cannot override them).
    private var processEventDelegate: TerminalProcessDelegate?
    private var processStarted = false
    private var settingsCancellables: Set<AnyCancellable> = []

    /// Shared mouse-click monitor for focus tracking. Installed once, handles all terminals.
    private static var sharedMouseMonitor: Any?
    private static var liveTerminals: Set<ObjectIdentifier> = []

    // MARK: - Init

    init(frame: NSRect, tabId: UUID, workingDirectory: String? = nil,
         sshConfig: SSHConnectionConfig? = nil) {
        self.surfaceId = UUID()
        self.tabId = tabId
        self.workingDirectory = workingDirectory
        self.sshConfig = sshConfig
        super.init(frame: frame)

        let delegate = TerminalProcessDelegate(terminalView: self, tabId: tabId)
        self.processEventDelegate = delegate
        processDelegate = delegate

        configureAppearance()

        // Re-apply appearance when relevant settings change
        let s = TerminalSettings.shared
        s.$backgroundColor.dropFirst().sink { [weak self] _ in self?.configureAppearance() }.store(in: &settingsCancellables)
        s.$foregroundColor.dropFirst().sink { [weak self] _ in self?.configureAppearance() }.store(in: &settingsCancellables)
        s.$fontName.dropFirst().sink { [weak self] _ in self?.configureAppearance() }.store(in: &settingsCancellables)
        s.$fontSize.dropFirst().sink { [weak self] _ in self?.configureAppearance() }.store(in: &settingsCancellables)
        s.$backgroundOpacity.dropFirst().sink { [weak self] _ in self?.configureAppearance() }.store(in: &settingsCancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Key handling

    /// Let Cmd+<key> shortcuts pass through to the menu bar instead of being
    /// consumed by the terminal. Without this, SwiftTerm sends Cmd+N etc to
    /// the shell process.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            // Let the main menu handle Cmd shortcuts
            if let mainMenu = NSApp.mainMenu, mainMenu.performKeyEquivalent(with: event) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    deinit {
        Self.liveTerminals.remove(ObjectIdentifier(self))
        if Self.liveTerminals.isEmpty, let monitor = Self.sharedMouseMonitor {
            NSEvent.removeMonitor(monitor)
            Self.sharedMouseMonitor = nil
        }
    }

    // MARK: - Appearance

    private func configureAppearance() {
        let settings = TerminalSettings.shared
        nativeBackgroundColor = settings.backgroundColor.withAlphaComponent(settings.backgroundOpacity)
        nativeForegroundColor = settings.foregroundColor

        let size = settings.fontSize

        // Skip font update if name and size haven't changed
        if font.fontName == settings.fontName && font.pointSize == size {
            return
        }

        // Try user's chosen font first
        if let f = NSFont(name: settings.fontName, size: size) {
            font = f
        } else {
            // Fallback chain: Nerd Fonts for Oh My Posh glyphs
            let fallbacks = [
                "CaskaydiaMono Nerd Font Mono",
                "CaskaydiaCove Nerd Font Mono",
                "JetBrainsMono Nerd Font Mono",
                "MesloLGS NF",
                "FiraCode Nerd Font Mono",
                "Hack Nerd Font Mono",
                "JetBrains Mono",
                "Menlo"
            ]
            for fontName in fallbacks {
                if let f = NSFont(name: fontName, size: size) {
                    font = f
                    break
                }
            }
        }
    }

    /// Install a single app-wide mouse monitor (shared across all terminals).
    private static func installSharedMonitorIfNeeded() {
        guard sharedMouseMonitor == nil else { return }
        sharedMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window,
                  let contentView = window.contentView,
                  let hitView = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil)) else {
                return event
            }
            // Walk up from hitView to find the nearest RobotermTerminal
            var view: NSView? = hitView
            while let v = view {
                if let terminal = v as? RobotermTerminal {
                    window.makeFirstResponder(terminal)
                    NotificationCenter.default.post(name: .terminalViewDidFocus, object: terminal)
                    break
                }
                view = v.superview
            }
            return event
        }
    }

    // MARK: - Shell startup

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            Self.liveTerminals.remove(ObjectIdentifier(self))
            return
        }

        // Register this terminal for the shared focus-tracking monitor
        Self.liveTerminals.insert(ObjectIdentifier(self))
        Self.installSharedMonitorIfNeeded()

        guard !processStarted else { return }
        processStarted = true

        if let ssh = sshConfig {
            // SSH direct process — start /usr/bin/ssh as the PTY process
            startProcess(
                executable: "/usr/bin/ssh",
                args: ssh.sshArgs,
                environment: buildEnvironment(),
                execName: "ssh",
                currentDirectory: workingDirectory
            )
        } else {
            // Local shell
            let settings = TerminalSettings.shared
            let shell = settings.shell

            startProcess(
                executable: shell,
                args: [],
                environment: buildEnvironment(),
                execName: (shell as NSString).lastPathComponent,
                currentDirectory: workingDirectory
            )

            // Auto-source ROS2 workspace after shell is ready
            if settings.ros2AutoSource && !settings.ros2WorkspacePath.isEmpty {
                let expanded = NSString(string: settings.ros2WorkspacePath).expandingTildeInPath
                let setupBash = expanded + "/install/setup.bash"
                let setupZsh  = expanded + "/install/setup.zsh"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    if shell.hasSuffix("zsh") && FileManager.default.fileExists(atPath: setupZsh) {
                        self?.send(txt: "source '\(setupZsh)'\n")
                    } else if FileManager.default.fileExists(atPath: setupBash) {
                        self?.send(txt: "source '\(setupBash)'\n")
                    }
                }
            }
        }

        window?.makeFirstResponder(self)
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["TERM_PROGRAM"] = "roboterm"
        env["ROBOTERM"] = "1"
        env["COLORTERM"] = "truecolor"

        // Fix locale warnings — ensure LC_* vars are set
        let locale = env["LANG"] ?? "en_US.UTF-8"
        env["LANG"] = locale
        env["LC_ALL"] = locale
        env["LC_CTYPE"] = "UTF-8"
        env["LC_COLLATE"] = locale

        // Local shell only: set tools path and ROS2 source
        if sshConfig == nil {
            if let toolsPath = Bundle.main.path(forResource: "roboterm-tools", ofType: "sh") {
                env["ROBOTERM_TOOLS"] = toolsPath
            } else {
                let candidates = [
                    "/Applications/ROBOTERM.app/Contents/Resources/roboterm-tools.sh",
                    Bundle.main.bundlePath + "/Contents/Resources/scripts/roboterm-tools.sh",
                ]
                for path in candidates where FileManager.default.fileExists(atPath: path) {
                    env["ROBOTERM_TOOLS"] = path
                    break
                }
            }

            // ROS2 auto-source: set env var so shell startup can source the workspace
            let settings = TerminalSettings.shared
            if settings.ros2AutoSource && !settings.ros2WorkspacePath.isEmpty {
                let expanded = NSString(string: settings.ros2WorkspacePath).expandingTildeInPath
                env["ROBOTERM_ROS2_SOURCE"] = expanded
            }
        }

        env.removeValue(forKey: "NO_COLOR")
        return env.map { "\($0.key)=\($0.value)" }
    }

    // MARK: - Public API

    /// Send text to the running terminal process.
    func sendText(_ text: String) {
        send(txt: text)
    }

    // MARK: - Right-click context menu

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        // Clipboard
        menu.addItem(withTitle: "Copy", action: #selector(copySelection(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(pasteClipboard(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // SSH-specific actions
        if sshConfig != nil {
            menu.addItem(withTitle: "Reconnect", action: #selector(ctxReconnectSSH(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Disconnect", action: #selector(ctxDisconnectSSH(_:)), keyEquivalent: "")
            menu.addItem(.separator())
        }

        // Splits
        menu.addItem(withTitle: "Split Right", action: #selector(ctxSplitRight(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Split Left", action: #selector(ctxSplitLeft(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Split Down", action: #selector(ctxSplitDown(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Split Up", action: #selector(ctxSplitUp(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // Terminal controls
        menu.addItem(withTitle: "Reset Terminal", action: #selector(clearTerminal(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(selectAllText(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // ROS2 quick actions
        let ros2Item = NSMenuItem(title: "ROS2", action: nil, keyEquivalent: "")
        let ros2Menu = NSMenu(title: "ROS2")
        ros2Menu.addItem(withTitle: "Node List", action: #selector(ctxRos2Nodes(_:)), keyEquivalent: "")
        ros2Menu.addItem(withTitle: "Topic List", action: #selector(ctxRos2Topics(_:)), keyEquivalent: "")
        ros2Menu.addItem(withTitle: "Service List", action: #selector(ctxRos2Services(_:)), keyEquivalent: "")
        ros2Menu.addItem(withTitle: "Doctor Report", action: #selector(ctxRos2Doctor(_:)), keyEquivalent: "")
        ros2Menu.addItem(.separator())
        ros2Menu.addItem(withTitle: "TF Tree", action: #selector(ctxRos2TfTree(_:)), keyEquivalent: "")
        ros2Menu.addItem(withTitle: "Topic Hz /scan", action: #selector(ctxRos2HzScan(_:)), keyEquivalent: "")
        ros2Item.submenu = ros2Menu
        menu.addItem(ros2Item)

        // Agent launch — built from settings
        let agentItem = NSMenuItem(title: "Launch Agent", action: nil, keyEquivalent: "")
        let agentMenu = NSMenu(title: "Launch Agent")
        for agent in TerminalSettings.shared.agents where agent.enabled {
            let item = NSMenuItem(title: agent.name.capitalized, action: #selector(ctxLaunchAgent(_:)), keyEquivalent: "")
            item.representedObject = agent.fullCommand
            agentMenu.addItem(item)
        }
        agentItem.submenu = agentMenu
        menu.addItem(agentItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func rightMouseUp(with event: NSEvent) {
        // Context menu is handled in rightMouseDown.
    }

    // MARK: - Context menu actions

    @objc private func copySelection(_ sender: Any?) {
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
    }

    @objc private func pasteClipboard(_ sender: Any?) {
        if let content = NSPasteboard.general.string(forType: .string) {
            send(txt: content)
        }
    }

    @objc private func selectAllText(_ sender: Any?) {
        selectAll(nil)
    }

    @objc private func clearTerminal(_ sender: Any?) {
        send(txt: "clear\n")
    }

    @objc private func ctxReconnectSSH(_ sender: Any?) {
        guard let config = sshConfig else { return }
        // Close this tab and open a fresh SSH connection
        guard let appDelegate = AppDelegate.shared else { return }
        let tabId = self.tabId
        for mgr in appDelegate.tabManagers {
            if mgr.tabs.contains(where: { $0.id == tabId }) {
                mgr.closeTab(tabId)
                mgr.createSSHTab(config: config)
                return
            }
        }
    }

    @objc private func ctxDisconnectSSH(_ sender: Any?) {
        // Send SSH escape sequence to disconnect: ~.
        send(txt: "\n~.\n")
    }

    private func sendCommandInTerminal(_ command: String) {
        send(txt: command + "\n")
    }

    @objc private func ctxRos2Nodes(_ sender: Any?) { sendCommandInTerminal("ros2 node list") }
    @objc private func ctxRos2Topics(_ sender: Any?) { sendCommandInTerminal("ros2 topic list") }
    @objc private func ctxRos2Services(_ sender: Any?) { sendCommandInTerminal("ros2 service list") }
    @objc private func ctxRos2Doctor(_ sender: Any?) { sendCommandInTerminal("ros2 doctor --report") }
    @objc private func ctxRos2TfTree(_ sender: Any?) { sendCommandInTerminal("ros2 run tf2_tools view_frames") }
    @objc private func ctxRos2HzScan(_ sender: Any?) { sendCommandInTerminal("ros2 topic hz /scan") }
    @objc private func ctxLaunchAgent(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        sendCommandInTerminal(command)
    }

    // Split context actions
    @objc private func ctxSplitRight(_ sender: Any?) { splitFromContext(direction: .horizontal) }
    @objc private func ctxSplitLeft(_ sender: Any?) { splitFromContext(direction: .horizontal) }
    @objc private func ctxSplitDown(_ sender: Any?) { splitFromContext(direction: .vertical) }
    @objc private func ctxSplitUp(_ sender: Any?) { splitFromContext(direction: .vertical) }

    private func splitFromContext(direction: SplitNode.SplitDirection) {
        guard let appDelegate = AppDelegate.shared else { return }
        for mgr in appDelegate.tabManagers {
            for ws in mgr.workspaces where ws.tabs.contains(where: { $0.id == tabId }) {
                ws.createSplitTab(nextTo: tabId, direction: direction)
                return
            }
        }
    }

    // MARK: - Open override: process exit (this one IS open in LocalProcessTerminalView)

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        // Let SwiftTerm perform its internal cleanup first.
        super.processTerminated(source, exitCode: exitCode)
        let tabId = self.tabId
        let isSSH = self.sshConfig != nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(
                name: .terminalProcessExited,
                object: self,
                userInfo: [
                    "tabId": tabId,
                    "isSSH": isSSH,
                    "exitCode": exitCode ?? 0
                ] as [String: Any]
            )
        }
    }
}

// MARK: - Private process event delegate

/// Separate delegate object that satisfies LocalProcessTerminalViewDelegate without
/// conflicting with LocalProcessTerminalView's own non-open method implementations.
private final class TerminalProcessDelegate: NSObject, LocalProcessTerminalViewDelegate {
    weak var terminalView: TerminalView?
    let tabId: UUID

    init(terminalView: TerminalView, tabId: UUID) {
        self.terminalView = terminalView
        self.tabId = tabId
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // LocalProcessTerminalView already handles PTY resize internally.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let tabId = self.tabId
        DispatchQueue.main.async { [weak self] in
            guard let tv = self?.terminalView else { return }
            NotificationCenter.default.post(
                name: .terminalTitleChanged,
                object: tv,
                userInfo: ["title": title, "tabId": tabId]
            )
        }
    }

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        let tabId = self.tabId
        DispatchQueue.main.async { [weak self] in
            guard let tv = self?.terminalView else { return }
            NotificationCenter.default.post(
                name: .terminalDirectoryChanged,
                object: tv,
                userInfo: ["directory": directory, "tabId": tabId]
            )
        }
    }

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        // Notification is posted by RobotermTerminal.processTerminated(_:exitCode:) override.
        // Do NOT post here — it would cause TabManager.closeTab() to fire twice.
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let terminalViewDidFocus     = Notification.Name("terminalViewDidFocus")
    static let terminalTitleChanged     = Notification.Name("terminalTitleChanged")
    static let terminalDirectoryChanged = Notification.Name("terminalDirectoryChanged")
    static let terminalProcessExited    = Notification.Name("terminalProcessExited")
}

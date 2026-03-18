import AppKit
import Foundation
import SwiftTerm

/// NSView that hosts a single terminal session using SwiftTerm's LocalProcessTerminalView.
///
/// All keyboard, mouse, scroll, and IME handling is provided automatically by SwiftTerm.
/// A private delegate bridge (TerminalProcessDelegate) captures process events and
/// forwards them as NotificationCenter posts so TabManager / Tab can react without
/// any direct reference to SwiftTerm types.
///
/// The public interface (tabId, surfaceId, sendText, workingDirectory) is identical
/// to the previous Ghostty-based implementation so all callers compile unchanged.
class RobotermTerminal: LocalProcessTerminalView {

    // MARK: - Public interface (kept for caller compatibility)

    /// Stable identifier used by SplitContainerView lookups.
    let surfaceId: UUID

    /// The Tab that owns this view.
    let tabId: UUID

    /// Optional working directory to start the shell in.
    var workingDirectory: String?

    // MARK: - Private

    /// Dedicated delegate object so we don't fight with LocalProcessTerminalView's own
    /// method implementations (most are public, not open, so we cannot override them).
    private var processEventDelegate: TerminalProcessDelegate?
    private var mouseDownMonitor: Any?
    private var trackingArea: NSTrackingArea?
    private var processStarted = false

    // MARK: - Init

    init(frame: NSRect, tabId: UUID, workingDirectory: String? = nil) {
        self.surfaceId = UUID()
        self.tabId = tabId
        self.workingDirectory = workingDirectory
        super.init(frame: frame)

        let delegate = TerminalProcessDelegate(terminalView: self, tabId: tabId)
        self.processEventDelegate = delegate
        processDelegate = delegate

        configureAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Appearance

    private func configureAppearance() {
        nativeBackgroundColor = TerminalSettings.shared.backgroundColor
        nativeForegroundColor = TerminalSettings.shared.foregroundColor

        // Use a Nerd Font for Oh My Posh glyphs — try installed ones
        let nerdFonts = [
            "CaskaydiaMono Nerd Font Mono",
            "CaskaydiaCove Nerd Font Mono",
            "JetBrainsMono Nerd Font Mono",
            "MesloLGS NF",
            "FiraCode Nerd Font Mono",
            "Hack Nerd Font Mono",
            "JetBrains Mono",
            "Menlo"
        ]
        let size = TerminalSettings.shared.fontSize
        for fontName in nerdFonts {
            if let f = NSFont(name: fontName, size: size) {
                font = f
                break
            }
        }
    }

    // MARK: - Shell startup

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            // View removed from hierarchy — clean up event monitor
            if let monitor = mouseDownMonitor {
                NSEvent.removeMonitor(monitor)
                mouseDownMonitor = nil
            }
            return
        }

        // Install a local event monitor to detect mouse clicks for focus tracking.
        // This avoids overriding mouseDown (which is public, not open in SwiftTerm).
        if mouseDownMonitor == nil {
            mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                if let hitView = self.window?.contentView?.hitTest(
                    self.window?.contentView?.convert(event.locationInWindow, from: nil) ?? .zero
                ), hitView === self || hitView.isDescendant(of: self) {
                    self.window?.makeFirstResponder(self)
                    NotificationCenter.default.post(name: .terminalViewDidFocus, object: self)
                }
                return event
            }
        }

        guard !processStarted else { return }
        processStarted = true

        let shell = TerminalSettings.shared.shell
        startProcess(
            executable: shell,
            args: [],
            environment: buildEnvironment(),
            execName: (shell as NSString).lastPathComponent,
            currentDirectory: workingDirectory
        )

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
        env.removeValue(forKey: "NO_COLOR")
        return env.map { "\($0.key)=\($0.value)" }
    }

    // MARK: - Public API

    /// Send text to the running shell (replaces former ghostty_surface_text).
    func sendText(_ text: String) {
        send(txt: text)
    }

    // MARK: - Right-click context menu

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        // Clipboard
        menu.addItem(withTitle: "Copy",  action: #selector(copySelection(_:)),  keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(pasteClipboard(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // Splits
        menu.addItem(withTitle: "Split Right", action: #selector(ctxSplitRight(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Split Left",  action: #selector(ctxSplitLeft(_:)),  keyEquivalent: "")
        menu.addItem(withTitle: "Split Down",  action: #selector(ctxSplitDown(_:)),  keyEquivalent: "")
        menu.addItem(withTitle: "Split Up",    action: #selector(ctxSplitUp(_:)),    keyEquivalent: "")
        menu.addItem(.separator())

        // Terminal controls
        menu.addItem(withTitle: "Reset Terminal", action: #selector(clearTerminal(_:)),  keyEquivalent: "")
        menu.addItem(withTitle: "Select All",     action: #selector(selectAllText(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        // ROS2 quick actions
        let ros2Item = NSMenuItem(title: "ROS2", action: nil, keyEquivalent: "")
        let ros2Menu = NSMenu(title: "ROS2")
        ros2Menu.addItem(withTitle: "Node List",      action: #selector(ctxRos2Nodes(_:)),    keyEquivalent: "")
        ros2Menu.addItem(withTitle: "Topic List",     action: #selector(ctxRos2Topics(_:)),   keyEquivalent: "")
        ros2Menu.addItem(withTitle: "Service List",   action: #selector(ctxRos2Services(_:)), keyEquivalent: "")
        ros2Menu.addItem(withTitle: "Doctor Report",  action: #selector(ctxRos2Doctor(_:)),   keyEquivalent: "")
        ros2Menu.addItem(.separator())
        ros2Menu.addItem(withTitle: "TF Tree",        action: #selector(ctxRos2TfTree(_:)),   keyEquivalent: "")
        ros2Menu.addItem(withTitle: "Topic Hz /scan", action: #selector(ctxRos2HzScan(_:)),   keyEquivalent: "")
        ros2Item.submenu = ros2Menu
        menu.addItem(ros2Item)

        // Agent launch
        let agentItem = NSMenuItem(title: "Launch Agent", action: nil, keyEquivalent: "")
        let agentMenu = NSMenu(title: "Launch Agent")
        agentMenu.addItem(withTitle: "Claude Code", action: #selector(ctxLaunchClaude(_:)), keyEquivalent: "")
        agentMenu.addItem(withTitle: "Codex",       action: #selector(ctxLaunchCodex(_:)),  keyEquivalent: "")
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

    private func sendCommandInTerminal(_ command: String) {
        send(txt: command + "\n")
    }

    @objc private func ctxRos2Nodes(_ sender: Any?)    { sendCommandInTerminal("ros2 node list") }
    @objc private func ctxRos2Topics(_ sender: Any?)   { sendCommandInTerminal("ros2 topic list") }
    @objc private func ctxRos2Services(_ sender: Any?) { sendCommandInTerminal("ros2 service list") }
    @objc private func ctxRos2Doctor(_ sender: Any?)   { sendCommandInTerminal("ros2 doctor --report") }
    @objc private func ctxRos2TfTree(_ sender: Any?)   { sendCommandInTerminal("ros2 run tf2_tools view_frames") }
    @objc private func ctxRos2HzScan(_ sender: Any?)   { sendCommandInTerminal("ros2 topic hz /scan") }
    @objc private func ctxLaunchClaude(_ sender: Any?) { sendCommandInTerminal("claude") }
    @objc private func ctxLaunchCodex(_ sender: Any?)  { sendCommandInTerminal("codex") }

    // Split context actions
    @objc private func ctxSplitRight(_ sender: Any?) { splitFromContext(direction: .horizontal) }
    @objc private func ctxSplitLeft(_ sender: Any?)  { splitFromContext(direction: .horizontal) }
    @objc private func ctxSplitDown(_ sender: Any?)  { splitFromContext(direction: .vertical) }
    @objc private func ctxSplitUp(_ sender: Any?)    { splitFromContext(direction: .vertical) }

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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(
                name: .terminalProcessExited,
                object: self,
                userInfo: ["tabId": tabId]
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
        // Also handled by TerminalView.processTerminated(_ source: LocalProcess, ...) override.
        // This delegate path is a secondary callback — both fire; we guard against double-close
        // in TabManager which is idempotent for closeTab().
        let tabId = self.tabId
        DispatchQueue.main.async { [weak self] in
            guard let tv = self?.terminalView else { return }
            NotificationCenter.default.post(
                name: .terminalProcessExited,
                object: tv,
                userInfo: ["tabId": tabId]
            )
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let terminalViewDidFocus     = Notification.Name("terminalViewDidFocus")
    static let terminalTitleChanged     = Notification.Name("terminalTitleChanged")
    static let terminalDirectoryChanged = Notification.Name("terminalDirectoryChanged")
    static let terminalProcessExited    = Notification.Name("terminalProcessExited")
}

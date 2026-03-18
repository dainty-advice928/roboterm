import AppKit
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    /// All tab managers (one per window).
    private(set) var tabManagers: [TabManager] = []
    private var settingsCancellables: Set<AnyCancellable> = []
    private var preferencesWindow: NSWindow?

    /// The tab manager for the currently focused window.
    var focusedTabManager: TabManager? {
        guard let keyWindow = NSApp.keyWindow else { return tabManagers.first }
        return tabManagers.first { $0.window === keyWindow }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Initialize terminal settings singleton
        _ = TerminalSettings.shared

        // Try to restore a previous session
        var restored = false
        if TerminalSettings.shared.restoreSessionOnLaunch,
           let session = SessionStore.restore() {
            restored = SessionStore.apply(session, to: self)
        }

        if !restored {
            createNewWindow()
        }

        // Build main menu
        NSApp.mainMenu = buildMainMenu()

        // Update window chrome when appearance settings change
        let updateWindowChrome = { [weak self] in
            guard let self else { return }
            let settings = TerminalSettings.shared
            let bgColor = settings.backgroundColor.withAlphaComponent(settings.backgroundOpacity)
            let isOpaque = settings.backgroundOpacity >= 1.0
            for mgr in self.tabManagers {
                mgr.window?.backgroundColor = bgColor
                mgr.window?.isOpaque = isOpaque
            }
        }
        let s = TerminalSettings.shared
        s.$backgroundColor.dropFirst().sink { _ in updateWindowChrome() }.store(in: &settingsCancellables)
        s.$backgroundOpacity.dropFirst().sink { _ in updateWindowChrome() }.store(in: &settingsCancellables)

        // Rebuild menu when SSH connections change (so the SSH submenu stays current)
        s.$sshConnections.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            NSApp.mainMenu = self.buildMainMenu()
        }.store(in: &settingsCancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if TerminalSettings.shared.saveSessionOnQuit {
            SessionStore.save(tabManagers: tabManagers)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Window management

    func registerTabManager(_ tabManager: TabManager) {
        tabManagers.append(tabManager)
    }

    func createWindowForTabManager(_ tabManager: TabManager) {
        if !tabManagers.contains(where: { $0 === tabManager }) {
            tabManagers.append(tabManager)
        }

        let contentView = ContentView(tabManager: tabManager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: contentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.title = "ROBOTERM"
        window.backgroundColor = TerminalSettings.shared.backgroundColor.withAlphaComponent(TerminalSettings.shared.backgroundOpacity)
        window.isOpaque = TerminalSettings.shared.backgroundOpacity >= 1.0
        window.delegate = self
        // Set frame to full visible area without zoom animation (zoom animation
        // can crash during dealloc if window state changes mid-animation).
        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: false)
        }
        window.makeKeyAndOrderFront(nil)

        tabManager.window = window
    }

    func createNewWindow() {
        let tabManager = TabManager()
        createWindowForTabManager(tabManager)
    }

    // MARK: - Menu actions

    @objc func newWindow(_ sender: Any?) {
        createNewWindow()
    }

    @objc func newTab(_ sender: Any?) {
        focusedTabManager?.createTab()
    }

    @objc func closeTab(_ sender: Any?) {
        guard let mgr = focusedTabManager, let tab = mgr.selectedTab else { return }
        mgr.closeTab(tab.id)
    }

    @objc func nextTab(_ sender: Any?) {
        focusedTabManager?.selectNextTab()
    }

    @objc func previousTab(_ sender: Any?) {
        focusedTabManager?.selectPreviousTab()
    }

    @objc func toggleSidebar(_ sender: Any?) {
        focusedTabManager?.isSidebarVisible.toggle()
    }

    @objc func closePane(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace,
              let tab = ws.selectedTab, ws.splitLayout != nil else { return }
        // Close the focused pane in a split — falls back to closeTab if only one pane
        mgr.closeTab(tab.id)
    }

    @objc func splitRight(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let tab = ws.selectedTab else { return }
        ws.createSplitTab(nextTo: tab.id, direction: .horizontal)
    }

    @objc func splitDown(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let tab = ws.selectedTab else { return }
        ws.createSplitTab(nextTo: tab.id, direction: .vertical)
    }

    @objc func nextPane(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let layout = ws.splitLayout else { return }
        let tabIds = layout.allTabIds
        guard tabIds.count > 1, let currentId = ws.selectedTabId,
              let index = tabIds.firstIndex(of: currentId) else { return }
        let nextId = tabIds[(index + 1) % tabIds.count]
        ws.selectedTabId = nextId
        if let tab = ws.tabs.first(where: { $0.id == nextId }) {
            tab.focus()
        }
    }

    @objc func previousPane(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let layout = ws.splitLayout else { return }
        let tabIds = layout.allTabIds
        guard tabIds.count > 1, let currentId = ws.selectedTabId,
              let index = tabIds.firstIndex(of: currentId) else { return }
        let prevId = tabIds[(index - 1 + tabIds.count) % tabIds.count]
        ws.selectedTabId = prevId
        if let tab = ws.tabs.first(where: { $0.id == prevId }) {
            tab.focus()
        }
    }

    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace else { return }
        let index = sender.tag - 1
        if sender.tag == 9 {
            // Cmd+9 = last tab
            if let last = ws.tabs.last { ws.selectTab(last.id) }
        } else if index >= 0, index < ws.tabs.count {
            ws.selectTab(ws.tabs[index].id)
        }
    }

    // MARK: - Zoom actions

    @objc func zoomIn(_ sender: Any?) {
        guard let mgr = focusedTabManager, let tab = mgr.selectedTab,
              let tv = tab.terminalView else { return }
        let current = tv.font.pointSize
        let newSize = current + 1
        tv.font = NSFont(name: tv.font.fontName, size: newSize) ?? NSFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
    }

    @objc func zoomOut(_ sender: Any?) {
        guard let mgr = focusedTabManager, let tab = mgr.selectedTab,
              let tv = tab.terminalView else { return }
        let current = tv.font.pointSize
        if current > 8 {
            let newSize = current - 1
            tv.font = NSFont(name: tv.font.fontName, size: newSize) ?? NSFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
        }
    }

    @objc func zoomReset(_ sender: Any?) {
        guard let mgr = focusedTabManager, let tab = mgr.selectedTab,
              let tv = tab.terminalView else { return }
        let settings = TerminalSettings.shared
        tv.font = NSFont(name: settings.fontName, size: settings.fontSize) ?? NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
    }

    // MARK: - Preferences

    @objc func openPreferences(_ sender: Any?) {
        // If the preferences window already exists, bring it to front
        if let existing = preferencesWindow {
            if !existing.isVisible {
                existing.center()
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create a standalone NSWindow hosting PreferencesView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ROBOTERM Preferences"
        window.contentView = NSHostingView(rootView: PreferencesView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow = window
    }

    // MARK: - Named session management

    @objc func saveNamedSession(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Save Session"
        alert.informativeText = "Enter a name for this session profile:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = "default"
        textField.placeholderString = "Session name"
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        SessionStore.saveNamed(name: name, tabManagers: tabManagers)
    }

    @objc func loadNamedSession(_ sender: Any?) {
        let sessions = SessionStore.listNamedSessions()
        guard !sessions.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Saved Sessions"
            alert.informativeText = "Save a session first using File → Save Session."
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Load Session"
        alert.informativeText = "Choose a session to restore:"
        alert.addButton(withTitle: "Load")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        for name in sessions { popup.addItem(withTitle: name) }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn,
              let selected = popup.selectedItem?.title else { return }

        if let session = SessionStore.restoreNamed(name: selected) {
            _ = SessionStore.apply(session, to: self)
        }
    }

    // MARK: - Robotics menu actions

    /// Run a command in a new tab (for TUI/long-running processes).
    private func runCommandInNewTab(_ command: String) {
        guard let mgr = focusedTabManager else { return }
        let tab = mgr.createTab()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            tab.terminalView?.sendText(command + "\n")
        }
    }

    /// Run a command in the current tab (for quick queries).
    private func runCommand(_ command: String) {
        guard let mgr = focusedTabManager,
              let tab = mgr.selectedTab else { return }
        tab.terminalView?.sendText(command + "\n")
    }

    // ROS2 Introspection — run in current tab (quick queries)
    @objc func ros2NodeList(_ sender: Any?) { runCommand("ros2 node list") }
    @objc func ros2TopicList(_ sender: Any?) { runCommand("ros2 topic list -v") }
    @objc func ros2ServiceList(_ sender: Any?) { runCommand("ros2 service list") }
    @objc func ros2ActionList(_ sender: Any?) { runCommand("ros2 action list -t") }
    @objc func ros2ParamList(_ sender: Any?) { runCommand("ros2 param list") }
    @objc func ros2InterfaceList(_ sender: Any?) { runCommand("ros2 interface list") }
    @objc func ros2Graph(_ sender: Any?) { runCommandInNewTab("rqt_graph") }

    // ROS2 Diagnostics — quick queries in current tab
    @objc func ros2Doctor(_ sender: Any?) { runCommand("ros2 doctor --report") }
    @objc func ros2DaemonStatus(_ sender: Any?) { runCommand("ros2 daemon status") }
    @objc func ros2Multicast(_ sender: Any?) { runCommandInNewTab("ros2 multicast receive") }
    @objc func ros2Wtf(_ sender: Any?) { runCommand("ros2 wtf") }
    @objc func ros2HzScan(_ sender: Any?) { runCommandInNewTab("ros2 topic hz /scan") }
    @objc func ros2HzCamera(_ sender: Any?) { runCommandInNewTab("ros2 topic hz /camera/image_raw") }
    @objc func ros2DelayTf(_ sender: Any?) { runCommandInNewTab("ros2 topic delay /tf") }

    // ROS2 Transforms
    @objc func ros2TfTree(_ sender: Any?) { runCommand("ros2 run tf2_tools view_frames") }
    @objc func ros2TfEcho(_ sender: Any?) { runCommandInNewTab("ros2 run tf2_ros tf2_echo base_link map") }
    @objc func ros2TfMonitor(_ sender: Any?) { runCommandInNewTab("ros2 run tf2_ros tf2_monitor") }

    // Launch & Build — new tab (long-running)
    @objc func ros2Launch(_ sender: Any?) { runCommandInNewTab("ros2 launch ") }
    @objc func ros2Run(_ sender: Any?) { runCommandInNewTab("ros2 run ") }
    @objc func colconBuild(_ sender: Any?) { runCommandInNewTab("colcon build --symlink-install") }
    @objc func colconBuildSelect(_ sender: Any?) { runCommandInNewTab("colcon build --packages-select ") }
    @objc func colconTest(_ sender: Any?) { runCommandInNewTab("colcon test") }

    // Bag Recording
    @objc func ros2BagRecord(_ sender: Any?) { runCommandInNewTab("ros2 bag record -a") }
    @objc func ros2BagRecordSelect(_ sender: Any?) { runCommandInNewTab("ros2 bag record ") }
    @objc func ros2BagPlay(_ sender: Any?) { runCommandInNewTab("ros2 bag play ") }
    @objc func ros2BagInfo(_ sender: Any?) { runCommandInNewTab("ros2 bag info ") }

    // Simulation
    @objc func launchGazebo(_ sender: Any?) { runCommandInNewTab("gz sim") }
    @objc func launchRViz2(_ sender: Any?) { runCommandInNewTab("rviz2") }
    @objc func launchRqt(_ sender: Any?) { runCommandInNewTab("rqt") }
    @objc func launchMuJoCo(_ sender: Any?) { runCommandInNewTab("python3 -m mujoco.viewer") }
    @objc func launchIsaacSim(_ sender: Any?) { runCommandInNewTab("isaac-sim") }

    // Docker
    @objc func dockerPs(_ sender: Any?) { runCommandInNewTab("docker compose ps") }
    @objc func animaComposeUp(_ sender: Any?) { runCommandInNewTab("docker compose up -d") }
    @objc func animaComposeDown(_ sender: Any?) { runCommandInNewTab("docker compose down") }
    @objc func animaLogs(_ sender: Any?) { runCommandInNewTab("docker compose logs -f --tail=50") }
    @objc func dockerPsAll(_ sender: Any?) { runCommandInNewTab("docker ps -a") }
    @objc func dockerImages(_ sender: Any?) { runCommandInNewTab("docker images") }

    // ANIMA
    @objc func animaStatus(_ sender: Any?) { runCommandInNewTab("docker compose ps") }
    @objc func animaCompile(_ sender: Any?) { runCommandInNewTab("anima compile") }
    @objc func animaPlug(_ sender: Any?) { runCommandInNewTab("anima plug") }

    // Hardware
    @objc func hwCamera(_ sender: Any?) { runCommandInNewTab("ros2 topic echo /camera/image_raw --once") }
    @objc func hwLidar(_ sender: Any?) { runCommandInNewTab("ros2 topic echo /scan --once") }
    @objc func hwImu(_ sender: Any?) { runCommandInNewTab("ros2 topic echo /imu/data --once") }
    @objc func hwJoy(_ sender: Any?) { runCommandInNewTab("ros2 topic echo /joy --once") }
    @objc func hwUsb(_ sender: Any?) { runCommandInNewTab("system_profiler SPUSBDataType") }
    @objc func hwSerial(_ sender: Any?) { runCommandInNewTab("ls -la /dev/tty.* /dev/cu.*") }
    /// Returns the focused tab manager, creating a new window if none exists.
    private func ensureTabManager() -> TabManager {
        if let mgr = focusedTabManager { return mgr }
        let mgr = TabManager()
        createWindowForTabManager(mgr)
        return mgr
    }

    @objc func connectSSHFromMenu(_ sender: NSMenuItem) {
        guard let config = sender.representedObject as? SSHConnectionConfig else { return }
        ensureTabManager().createSSHTab(config: config)
    }

    @objc func hwSSH(_ sender: Any?) {
        // If SSH connections are configured, connect to the first one; otherwise open preferences
        let connections = TerminalSettings.shared.sshConnections
        if let first = connections.first, !first.host.isEmpty {
            ensureTabManager().createSSHTab(config: first)
        } else {
            openPreferences(nil)
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        tabManagers.removeAll { $0.window === window }
    }
}

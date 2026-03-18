import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    /// All tab managers (one per window).
    private(set) var tabManagers: [TabManager] = []

    /// The tab manager for the currently focused window.
    var focusedTabManager: TabManager? {
        guard let keyWindow = NSApp.keyWindow else { return tabManagers.first }
        return tabManagers.first { $0.window === keyWindow }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Force Ghostty initialization
        _ = GhosttyManager.shared

        // Try to restore a previous session
        var restored = false
        if let session = SessionStore.restore() {
            restored = SessionStore.apply(session, to: self)
            if restored {
                SessionStore.clear()
            }
        }

        if !restored {
            createNewWindow()
        }

        // Build main menu
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionStore.save(tabManagers: tabManagers)
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
        window.backgroundColor = GhosttyManager.shared.backgroundColor
        window.isOpaque = GhosttyManager.shared.backgroundOpacity >= 1.0
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        window.zoom(nil)

        tabManager.window = window
    }

    func createNewWindow() {
        let tabManager = TabManager()
        createWindowForTabManager(tabManager)
    }

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ROBOTERM", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ROBOTERM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "t")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeTab(_:)), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // View menu (splits)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Split Right", action: #selector(splitRight(_:)), keyEquivalent: "d")
        viewMenu.addItem(withTitle: "Split Down", action: #selector(splitDown(_:)), keyEquivalent: "d")
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Next Pane", action: #selector(nextPane(_:)), keyEquivalent: "]")
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(withTitle: "Previous Pane", action: #selector(previousPane(_:)), keyEquivalent: "[")
        viewMenu.items.last?.keyEquivalentModifierMask = [.command, .option]
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Next Tab", action: #selector(nextTab(_:)), keyEquivalent: "}")
        windowMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(withTitle: "Previous Tab", action: #selector(previousTab(_:)), keyEquivalent: "{")
        windowMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        windowMenu.addItem(.separator())
        for i in 1...9 {
            windowMenu.addItem(withTitle: "Tab \(i)", action: #selector(selectTabByNumber(_:)), keyEquivalent: "\(i)")
            windowMenu.items.last?.tag = i
        }
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // Edit menu (for Copy/Paste to work)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Robotics menu
        let roboticsMenu = NSMenu(title: "Robotics")

        // ROS2 Introspection
        let ros2IntrospectItem = NSMenuItem(title: "ROS2 Introspect", action: nil, keyEquivalent: "")
        let ros2IntrospectMenu = NSMenu(title: "ROS2 Introspect")
        ros2IntrospectMenu.addItem(withTitle: "Node List", action: #selector(ros2NodeList(_:)), keyEquivalent: "")
        ros2IntrospectMenu.addItem(withTitle: "Topic List (verbose)", action: #selector(ros2TopicList(_:)), keyEquivalent: "")
        ros2IntrospectMenu.addItem(withTitle: "Service List", action: #selector(ros2ServiceList(_:)), keyEquivalent: "")
        ros2IntrospectMenu.addItem(withTitle: "Action List", action: #selector(ros2ActionList(_:)), keyEquivalent: "")
        ros2IntrospectMenu.addItem(withTitle: "Parameter List", action: #selector(ros2ParamList(_:)), keyEquivalent: "")
        ros2IntrospectMenu.addItem(withTitle: "Interface List", action: #selector(ros2InterfaceList(_:)), keyEquivalent: "")
        ros2IntrospectMenu.addItem(.separator())
        ros2IntrospectMenu.addItem(withTitle: "Node Graph (rqt_graph)", action: #selector(ros2Graph(_:)), keyEquivalent: "")
        ros2IntrospectItem.submenu = ros2IntrospectMenu
        roboticsMenu.addItem(ros2IntrospectItem)

        // ROS2 Diagnostics
        let ros2DiagItem = NSMenuItem(title: "ROS2 Diagnostics", action: nil, keyEquivalent: "")
        let ros2DiagMenu = NSMenu(title: "ROS2 Diagnostics")
        ros2DiagMenu.addItem(withTitle: "Doctor Report", action: #selector(ros2Doctor(_:)), keyEquivalent: "")
        ros2DiagMenu.addItem(withTitle: "Daemon Status", action: #selector(ros2DaemonStatus(_:)), keyEquivalent: "")
        ros2DiagMenu.addItem(withTitle: "Multicast Test", action: #selector(ros2Multicast(_:)), keyEquivalent: "")
        ros2DiagMenu.addItem(withTitle: "wtf (diagnostic dump)", action: #selector(ros2Wtf(_:)), keyEquivalent: "")
        ros2DiagMenu.addItem(.separator())
        ros2DiagMenu.addItem(withTitle: "Topic Hz /scan", action: #selector(ros2HzScan(_:)), keyEquivalent: "")
        ros2DiagMenu.addItem(withTitle: "Topic Hz /camera/image_raw", action: #selector(ros2HzCamera(_:)), keyEquivalent: "")
        ros2DiagMenu.addItem(withTitle: "Topic Delay /tf", action: #selector(ros2DelayTf(_:)), keyEquivalent: "")
        ros2DiagItem.submenu = ros2DiagMenu
        roboticsMenu.addItem(ros2DiagItem)

        // ROS2 Transforms
        let ros2TfItem = NSMenuItem(title: "ROS2 Transforms", action: nil, keyEquivalent: "")
        let ros2TfMenu = NSMenu(title: "ROS2 Transforms")
        ros2TfMenu.addItem(withTitle: "TF Tree (view_frames)", action: #selector(ros2TfTree(_:)), keyEquivalent: "")
        ros2TfMenu.addItem(withTitle: "TF Echo base_link → map", action: #selector(ros2TfEcho(_:)), keyEquivalent: "")
        ros2TfMenu.addItem(withTitle: "TF Monitor", action: #selector(ros2TfMonitor(_:)), keyEquivalent: "")
        ros2TfItem.submenu = ros2TfMenu
        roboticsMenu.addItem(ros2TfItem)
        roboticsMenu.addItem(.separator())

        // Launch & Run
        let launchItem = NSMenuItem(title: "Launch & Run", action: nil, keyEquivalent: "")
        let launchMenu = NSMenu(title: "Launch & Run")
        launchMenu.addItem(withTitle: "ros2 launch...", action: #selector(ros2Launch(_:)), keyEquivalent: "l")
        launchMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        launchMenu.addItem(withTitle: "ros2 run...", action: #selector(ros2Run(_:)), keyEquivalent: "")
        launchMenu.addItem(.separator())
        launchMenu.addItem(withTitle: "colcon build", action: #selector(colconBuild(_:)), keyEquivalent: "b")
        launchMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        launchMenu.addItem(withTitle: "colcon build --packages-select...", action: #selector(colconBuildSelect(_:)), keyEquivalent: "")
        launchMenu.addItem(withTitle: "colcon test", action: #selector(colconTest(_:)), keyEquivalent: "")
        launchItem.submenu = launchMenu
        roboticsMenu.addItem(launchItem)

        // Bag Recording
        let bagItem = NSMenuItem(title: "Bag Recording", action: nil, keyEquivalent: "")
        let bagMenu = NSMenu(title: "Bag Recording")
        bagMenu.addItem(withTitle: "Record All Topics", action: #selector(ros2BagRecord(_:)), keyEquivalent: "")
        bagMenu.addItem(withTitle: "Record Select Topics...", action: #selector(ros2BagRecordSelect(_:)), keyEquivalent: "")
        bagMenu.addItem(withTitle: "Play Bag...", action: #selector(ros2BagPlay(_:)), keyEquivalent: "")
        bagMenu.addItem(withTitle: "Bag Info...", action: #selector(ros2BagInfo(_:)), keyEquivalent: "")
        bagItem.submenu = bagMenu
        roboticsMenu.addItem(bagItem)
        roboticsMenu.addItem(.separator())

        // Simulation
        let simItem = NSMenuItem(title: "Simulation", action: nil, keyEquivalent: "")
        let simMenu = NSMenu(title: "Simulation")
        simMenu.addItem(withTitle: "Gazebo Sim", action: #selector(launchGazebo(_:)), keyEquivalent: "")
        simMenu.addItem(withTitle: "RViz2", action: #selector(launchRViz2(_:)), keyEquivalent: "")
        simMenu.addItem(withTitle: "rqt", action: #selector(launchRqt(_:)), keyEquivalent: "")
        simMenu.addItem(withTitle: "MuJoCo", action: #selector(launchMuJoCo(_:)), keyEquivalent: "")
        simMenu.addItem(withTitle: "Isaac Sim", action: #selector(launchIsaacSim(_:)), keyEquivalent: "")
        simItem.submenu = simMenu
        roboticsMenu.addItem(simItem)
        roboticsMenu.addItem(.separator())

        // Docker
        let dockerItem = NSMenuItem(title: "Docker", action: nil, keyEquivalent: "")
        let dockerMenu = NSMenu(title: "Docker")
        dockerMenu.addItem(withTitle: "docker compose ps", action: #selector(dockerPs(_:)), keyEquivalent: "")
        dockerMenu.addItem(withTitle: "docker compose up -d", action: #selector(animaComposeUp(_:)), keyEquivalent: "")
        dockerMenu.addItem(withTitle: "docker compose down", action: #selector(animaComposeDown(_:)), keyEquivalent: "")
        dockerMenu.addItem(withTitle: "docker compose logs -f", action: #selector(animaLogs(_:)), keyEquivalent: "")
        dockerMenu.addItem(.separator())
        dockerMenu.addItem(withTitle: "docker ps", action: #selector(dockerPsAll(_:)), keyEquivalent: "")
        dockerMenu.addItem(withTitle: "docker images", action: #selector(dockerImages(_:)), keyEquivalent: "")
        dockerItem.submenu = dockerMenu
        roboticsMenu.addItem(dockerItem)

        // ANIMA
        let animaItem = NSMenuItem(title: "ANIMA Suite", action: nil, keyEquivalent: "")
        let animaMenu = NSMenu(title: "ANIMA Suite")
        animaMenu.addItem(withTitle: "Module Status", action: #selector(animaStatus(_:)), keyEquivalent: "")
        animaMenu.addItem(withTitle: "ANIMA Compile", action: #selector(animaCompile(_:)), keyEquivalent: "")
        animaMenu.addItem(withTitle: "ANIMA Plug", action: #selector(animaPlug(_:)), keyEquivalent: "")
        animaItem.submenu = animaMenu
        roboticsMenu.addItem(animaItem)
        roboticsMenu.addItem(.separator())

        // Hardware
        let hwItem = NSMenuItem(title: "Hardware", action: nil, keyEquivalent: "")
        let hwMenu = NSMenu(title: "Hardware")
        hwMenu.addItem(withTitle: "Camera Status", action: #selector(hwCamera(_:)), keyEquivalent: "")
        hwMenu.addItem(withTitle: "LiDAR Status", action: #selector(hwLidar(_:)), keyEquivalent: "")
        hwMenu.addItem(withTitle: "IMU Status", action: #selector(hwImu(_:)), keyEquivalent: "")
        hwMenu.addItem(withTitle: "Joy/Gamepad", action: #selector(hwJoy(_:)), keyEquivalent: "")
        hwMenu.addItem(.separator())
        hwMenu.addItem(withTitle: "USB Devices (system_profiler)", action: #selector(hwUsb(_:)), keyEquivalent: "")
        hwMenu.addItem(withTitle: "Serial Ports", action: #selector(hwSerial(_:)), keyEquivalent: "")
        hwMenu.addItem(.separator())
        hwMenu.addItem(withTitle: "SSH to Robot...", action: #selector(hwSSH(_:)), keyEquivalent: "")
        hwItem.submenu = hwMenu
        roboticsMenu.addItem(hwItem)

        let roboticsMenuItem = NSMenuItem()
        roboticsMenuItem.submenu = roboticsMenu
        mainMenu.addItem(roboticsMenuItem)

        return mainMenu
    }

    // MARK: - Menu actions

    @objc private func newWindow(_ sender: Any?) {
        createNewWindow()
    }

    @objc private func newTab(_ sender: Any?) {
        focusedTabManager?.createTab()
    }

    @objc private func closeTab(_ sender: Any?) {
        guard let mgr = focusedTabManager, let tab = mgr.selectedTab else { return }
        mgr.closeTab(tab.id)
    }

    @objc private func nextTab(_ sender: Any?) {
        focusedTabManager?.selectNextTab()
    }

    @objc private func previousTab(_ sender: Any?) {
        focusedTabManager?.selectPreviousTab()
    }

    @objc private func splitRight(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let tab = ws.selectedTab else { return }
        ws.createSplitTab(nextTo: tab.id, direction: .horizontal)
    }

    @objc private func splitDown(_ sender: Any?) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace, let tab = ws.selectedTab else { return }
        ws.createSplitTab(nextTo: tab.id, direction: .vertical)
    }

    @objc private func nextPane(_ sender: Any?) {
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

    @objc private func previousPane(_ sender: Any?) {
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

    @objc private func selectTabByNumber(_ sender: NSMenuItem) {
        guard let mgr = focusedTabManager, let ws = mgr.selectedWorkspace else { return }
        let index = sender.tag - 1
        if sender.tag == 9 {
            // Cmd+9 = last tab
            if let last = ws.tabs.last { ws.selectTab(last.id) }
        } else if index >= 0, index < ws.tabs.count {
            ws.selectTab(ws.tabs[index].id)
        }
    }

    // MARK: - Robotics menu actions

    /// Run a command in a new tab (for TUI/long-running processes).
    private func runCommandInNewTab(_ command: String) {
        guard let mgr = focusedTabManager else { return }
        let tab = mgr.createTab()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let surface = tab.terminalView?.surface {
                let cmd = command + "\n"
                cmd.withCString { ptr in
                    ghostty_surface_text(surface, ptr, UInt(cmd.utf8.count))
                }
            }
        }
    }

    /// Run a command in the current tab (for quick queries).
    private func runCommand(_ command: String) {
        guard let mgr = focusedTabManager,
              let tab = mgr.selectedTab,
              let surface = tab.terminalView?.surface else { return }
        let cmd = command + "\n"
        cmd.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(cmd.utf8.count))
        }
    }

    // ROS2 Introspection — run in current tab (quick queries)
    @objc private func ros2NodeList(_ sender: Any?) { runCommand("ros2 node list") }
    @objc private func ros2TopicList(_ sender: Any?) { runCommand("ros2 topic list -v") }
    @objc private func ros2ServiceList(_ sender: Any?) { runCommand("ros2 service list") }
    @objc private func ros2ActionList(_ sender: Any?) { runCommand("ros2 action list -t") }
    @objc private func ros2ParamList(_ sender: Any?) { runCommand("ros2 param list") }
    @objc private func ros2InterfaceList(_ sender: Any?) { runCommand("ros2 interface list") }
    @objc private func ros2Graph(_ sender: Any?) { runCommandInNewTab("rqt_graph") }

    // ROS2 Diagnostics — quick queries in current tab
    @objc private func ros2Doctor(_ sender: Any?) { runCommand("ros2 doctor --report") }
    @objc private func ros2DaemonStatus(_ sender: Any?) { runCommand("ros2 daemon status") }
    @objc private func ros2Multicast(_ sender: Any?) { runCommandInNewTab("ros2 multicast receive") }
    @objc private func ros2Wtf(_ sender: Any?) { runCommand("ros2 wtf") }
    @objc private func ros2HzScan(_ sender: Any?) { runCommandInNewTab("ros2 topic hz /scan") }
    @objc private func ros2HzCamera(_ sender: Any?) { runCommandInNewTab("ros2 topic hz /camera/image_raw") }
    @objc private func ros2DelayTf(_ sender: Any?) { runCommandInNewTab("ros2 topic delay /tf") }

    // ROS2 Transforms
    @objc private func ros2TfTree(_ sender: Any?) { runCommand("ros2 run tf2_tools view_frames") }
    @objc private func ros2TfEcho(_ sender: Any?) { runCommandInNewTab("ros2 run tf2_ros tf2_echo base_link map") }
    @objc private func ros2TfMonitor(_ sender: Any?) { runCommandInNewTab("ros2 run tf2_ros tf2_monitor") }

    // Launch & Build — new tab (long-running)
    @objc private func ros2Launch(_ sender: Any?) { runCommandInNewTab("ros2 launch ") }
    @objc private func ros2Run(_ sender: Any?) { runCommandInNewTab("ros2 run ") }
    @objc private func colconBuild(_ sender: Any?) { runCommandInNewTab("colcon build --symlink-install") }
    @objc private func colconBuildSelect(_ sender: Any?) { runCommandInNewTab("colcon build --packages-select ") }
    @objc private func colconTest(_ sender: Any?) { runCommandInNewTab("colcon test") }

    // Bag Recording
    @objc private func ros2BagRecord(_ sender: Any?) { runCommandInNewTab("ros2 bag record -a") }
    @objc private func ros2BagRecordSelect(_ sender: Any?) { runCommandInNewTab("ros2 bag record ") }
    @objc private func ros2BagPlay(_ sender: Any?) { runCommandInNewTab("ros2 bag play ") }
    @objc private func ros2BagInfo(_ sender: Any?) { runCommandInNewTab("ros2 bag info ") }

    // Simulation
    @objc private func launchGazebo(_ sender: Any?) { runCommandInNewTab("gz sim") }
    @objc private func launchRViz2(_ sender: Any?) { runCommandInNewTab("rviz2") }
    @objc private func launchRqt(_ sender: Any?) { runCommandInNewTab("rqt") }
    @objc private func launchMuJoCo(_ sender: Any?) { runCommandInNewTab("python3 -m mujoco.viewer") }
    @objc private func launchIsaacSim(_ sender: Any?) { runCommandInNewTab("isaac-sim") }

    // Docker
    @objc private func dockerPs(_ sender: Any?) { runCommandInNewTab("docker compose ps") }
    @objc private func animaComposeUp(_ sender: Any?) { runCommandInNewTab("docker compose up -d") }
    @objc private func animaComposeDown(_ sender: Any?) { runCommandInNewTab("docker compose down") }
    @objc private func animaLogs(_ sender: Any?) { runCommandInNewTab("docker compose logs -f --tail=50") }
    @objc private func dockerPsAll(_ sender: Any?) { runCommandInNewTab("docker ps -a") }
    @objc private func dockerImages(_ sender: Any?) { runCommandInNewTab("docker images") }

    // ANIMA
    @objc private func animaStatus(_ sender: Any?) { runCommandInNewTab("docker compose ps") }
    @objc private func animaCompile(_ sender: Any?) { runCommandInNewTab("anima compile") }
    @objc private func animaPlug(_ sender: Any?) { runCommandInNewTab("anima plug") }

    // Hardware
    @objc private func hwCamera(_ sender: Any?) { runCommandInNewTab("ros2 topic echo /camera/image_raw --once") }
    @objc private func hwLidar(_ sender: Any?) { runCommandInNewTab("ros2 topic echo /scan --once") }
    @objc private func hwImu(_ sender: Any?) { runCommandInNewTab("ros2 topic echo /imu/data --once") }
    @objc private func hwJoy(_ sender: Any?) { runCommandInNewTab("ros2 topic echo /joy --once") }
    @objc private func hwUsb(_ sender: Any?) { runCommandInNewTab("system_profiler SPUSBDataType") }
    @objc private func hwSerial(_ sender: Any?) { runCommandInNewTab("ls -la /dev/tty.* /dev/cu.*") }
    @objc private func hwSSH(_ sender: Any?) { runCommandInNewTab("ssh ") }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        tabManagers.removeAll { $0.window === window }
    }
}

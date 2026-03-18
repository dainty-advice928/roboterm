import AppKit

// ROBOTERM AppleScript hooks.
// Cocoa scripting resolves objects via ObjC selectors derived from Roboterm.sdef.

// MARK: - Windows

@MainActor
extension NSApplication {
    @objc(scriptWindows)
    var scriptWindows: [ScriptWindow] {
        guard let appDelegate = AppDelegate.shared else { return [] }
        return appDelegate.tabManagers.map { ScriptWindow(tabManager: $0) }
    }

    @objc(frontWindow)
    var frontWindow: ScriptWindow? {
        guard let appDelegate = AppDelegate.shared else { return nil }
        guard let mgr = appDelegate.focusedTabManager else { return scriptWindows.first }
        return ScriptWindow(tabManager: mgr)
    }

    @objc(valueInScriptWindowsWithUniqueID:)
    func valueInScriptWindows(uniqueID: String) -> ScriptWindow? {
        scriptWindows.first(where: { $0.stableID == uniqueID })
    }
}

// MARK: - Terminals

@MainActor
extension NSApplication {
    @objc(terminals)
    var terminals: [ScriptTerminal] {
        guard let appDelegate = AppDelegate.shared else { return [] }
        return appDelegate.tabManagers.flatMap { $0.tabs }.map { ScriptTerminal(tab: $0) }
    }

    @objc(valueInTerminalsWithUniqueID:)
    func valueInTerminals(uniqueID: String) -> ScriptTerminal? {
        guard let appDelegate = AppDelegate.shared else { return nil }
        return appDelegate.tabManagers
            .flatMap { $0.tabs }
            .first(where: { $0.id.uuidString == uniqueID })
            .map { ScriptTerminal(tab: $0) }
    }
}

// MARK: - Commands

@MainActor
extension NSApplication {
    @objc(handleNewWindowScriptCommand:)
    func handleNewWindowScriptCommand(_ command: NSScriptCommand) -> ScriptWindow? {
        guard let appDelegate = AppDelegate.shared else {
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = "App delegate unavailable."
            return nil
        }

        // Parse optional configuration
        var workingDir: String?
        if let config = command.evaluatedArguments?["configuration"] as? NSDictionary,
           let raw = config as? [String: Any],
           let dir = raw["workingDirectory"] as? String, !dir.isEmpty {
            workingDir = dir
        }

        let tabManager = TabManager()

        // Apply working directory if configured
        if let dir = workingDir, let ws = tabManager.selectedWorkspace {
            ws.directory = dir
        }

        appDelegate.createWindowForTabManager(tabManager)

        // Send initial input if configured
        if let config = command.evaluatedArguments?["configuration"] as? NSDictionary,
           let raw = config as? [String: Any],
           let input = raw["initialInput"] as? String, !input.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let tab = tabManager.selectedTab {
                    ScriptTerminal(tab: tab).sendText(input)
                }
            }
        }

        return ScriptWindow(tabManager: tabManager)
    }

    @objc(handleNewTabScriptCommand:)
    func handleNewTabScriptCommand(_ command: NSScriptCommand) -> ScriptTab? {
        guard let appDelegate = AppDelegate.shared else {
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = "App delegate unavailable."
            return nil
        }

        // Find target window
        let targetMgr: TabManager
        if let targetWindow = command.evaluatedArguments?["window"] as? ScriptWindow,
           let mgr = appDelegate.tabManagers.first(where: {
               ScriptWindow(tabManager: $0).stableID == targetWindow.stableID
           }) {
            targetMgr = mgr
        } else {
            targetMgr = appDelegate.focusedTabManager ?? appDelegate.tabManagers.first ?? {
                let mgr = TabManager()
                appDelegate.createWindowForTabManager(mgr)
                return mgr
            }()
        }

        // Parse optional configuration
        var workingDir = TerminalSettings.shared.defaultWorkingDirectory
        if let config = command.evaluatedArguments?["configuration"] as? NSDictionary,
           let raw = config as? [String: Any],
           let dir = raw["workingDirectory"] as? String, !dir.isEmpty {
            workingDir = dir
        }

        let ws = targetMgr.createWorkspace(directory: workingDir)
        ws.createTab()

        let window = ScriptWindow(tabManager: targetMgr)
        let index = (targetMgr.workspaces.firstIndex(where: { $0.id == ws.id }) ?? 0) + 1
        return ScriptTab(window: window, workspace: ws, index: index, tabManager: targetMgr)
    }

    @objc(handleQuitScriptCommand:)
    func handleQuitScriptCommand(_ command: NSScriptCommand) {
        terminate(nil)
    }
}

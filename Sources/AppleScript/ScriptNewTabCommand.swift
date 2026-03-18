import AppKit

/// Handler for `new tab` AppleScript command.
/// Uses NSScriptCommand subclass pattern for reliable dispatch in SwiftUI apps.
@MainActor
@objc(RobotermScriptNewTabCommand)
final class ScriptNewTabCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let appDelegate = AppDelegate.shared else {
            scriptErrorNumber = errAEEventFailed
            scriptErrorString = "App delegate unavailable."
            return nil
        }

        // Find target window
        let targetMgr: TabManager
        if let targetWindow = evaluatedArguments?["window"] as? ScriptWindow,
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
        if let config = evaluatedArguments?["configuration"] as? NSDictionary,
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
}

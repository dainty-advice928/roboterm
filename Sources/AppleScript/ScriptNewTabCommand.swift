import AppKit

/// Handler for `new tab` AppleScript command.
@objc(RobotermScriptNewTabCommand)
final class ScriptNewTabCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let appDelegate = MainActor.assumeIsolated({ AppDelegate.shared }) else {
            scriptErrorNumber = errAEEventFailed
            scriptErrorString = "App delegate unavailable."
            return nil
        }

        let targetMgr: TabManager = MainActor.assumeIsolated {
            if let targetWindow = self.evaluatedArguments?["window"] as? ScriptWindow,
               let mgr = appDelegate.tabManagers.first(where: {
                   ScriptWindow(tabManager: $0).stableID == targetWindow.stableID
               }) {
                return mgr
            }
            return appDelegate.focusedTabManager ?? appDelegate.tabManagers.first ?? {
                let mgr = TabManager()
                appDelegate.createWindowForTabManager(mgr)
                return mgr
            }()
        }

        MainActor.assumeIsolated {
            var workingDir = TerminalSettings.shared.defaultWorkingDirectory
            if let config = self.evaluatedArguments?["configuration"] as? NSDictionary,
               let raw = config as? [String: Any],
               let dir = raw["workingDirectory"] as? String, !dir.isEmpty {
                workingDir = dir
            }

            let ws = targetMgr.createWorkspace(directory: workingDir)
            ws.createTab()
        }

        // Same objectSpecifier limitation as new window — return nil
        return nil
    }
}

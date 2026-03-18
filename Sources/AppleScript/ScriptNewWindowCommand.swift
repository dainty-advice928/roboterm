import AppKit

/// Handler for `new window` AppleScript command.
/// Uses NSScriptCommand subclass pattern for reliable dispatch in SwiftUI apps.
@MainActor
@objc(RobotermScriptNewWindowCommand)
final class ScriptNewWindowCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let appDelegate = AppDelegate.shared else {
            scriptErrorNumber = errAEEventFailed
            scriptErrorString = "App delegate unavailable."
            return nil
        }

        // Parse optional configuration
        var workingDir: String?
        if let config = evaluatedArguments?["configuration"] as? NSDictionary,
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
        if let config = evaluatedArguments?["configuration"] as? NSDictionary,
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
}

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


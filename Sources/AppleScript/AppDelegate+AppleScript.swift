import AppKit

// ROBOTERM AppleScript hooks.
// Cocoa Scripting resolves elements/properties via KVC on the object specified
// in the SDEF. Since SDEF maps "application" to NSApplication, we provide
// properties as NSApplication extensions. We ALSO implement delegateHandlesKey
// on AppDelegate as a fallback.

// MARK: - Delegate Handles Key (fallback path)

extension AppDelegate {
    /// Tells Cocoa Scripting to ask our AppDelegate for these properties.
    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        switch key {
        case "scriptWindows", "frontWindow", "terminals":
            return true
        default:
            return false
        }
    }

    // Delegate-side copies for the fallback path
    @objc(scriptWindows)
    var scriptWindows: [ScriptWindow] {
        tabManagers.map { ScriptWindow(tabManager: $0) }
    }

    @objc(frontWindow)
    var frontWindow: ScriptWindow? {
        guard let mgr = focusedTabManager else { return scriptWindows.first }
        return ScriptWindow(tabManager: mgr)
    }

    @objc(valueInScriptWindowsWithUniqueID:)
    func valueInScriptWindows(uniqueID: String) -> ScriptWindow? {
        scriptWindows.first(where: { $0.stableID == uniqueID })
    }

    @objc(terminals)
    var terminals: [ScriptTerminal] {
        tabManagers.flatMap { $0.tabs }.map { ScriptTerminal(tab: $0) }
    }

    @objc(valueInTerminalsWithUniqueID:)
    func valueInTerminals(uniqueID: String) -> ScriptTerminal? {
        tabManagers
            .flatMap { $0.tabs }
            .first(where: { $0.id.uuidString == uniqueID })
            .map { ScriptTerminal(tab: $0) }
    }
}

// MARK: - NSApplication KVC path (primary path)
// These expose properties directly on NSApplication for Cocoa Scripting KVC.
// No @MainActor on the extension — this prevents KVC/ObjC runtime access issues.

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

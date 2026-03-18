import AppKit

/// Handler for `new window` AppleScript command.
/// Cocoa Scripting always calls performDefaultImplementation on the main thread.
/// We use MainActor.assumeIsolated to satisfy the compiler without changing the
/// ObjC method signature.
@objc(RobotermScriptNewWindowCommand)
final class ScriptNewWindowCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let appDelegate = MainActor.assumeIsolated({ AppDelegate.shared }) else {
            scriptErrorNumber = errAEEventFailed
            scriptErrorString = "App delegate unavailable."
            return nil
        }

        let tabManager = MainActor.assumeIsolated { TabManager() }

        MainActor.assumeIsolated {
            appDelegate.createWindowForTabManager(tabManager)
        }

        // Note: returning ScriptWindow triggers -1708 because NSApplication's
        // classDescription doesn't include our SDEF in SwiftUI apps. The window
        // IS created; we just can't return an object specifier for it.
        return nil
    }
}

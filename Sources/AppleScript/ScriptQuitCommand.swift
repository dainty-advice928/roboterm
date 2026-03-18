import AppKit

/// Handler for `quit` AppleScript command.
/// Uses NSScriptCommand subclass pattern for reliable dispatch in SwiftUI apps.
@MainActor
@objc(RobotermScriptQuitCommand)
final class ScriptQuitCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        NSApplication.shared.terminate(nil)
        return nil
    }
}

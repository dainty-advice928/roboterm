import AppKit

/// Handler for `quit` AppleScript command.
@objc(RobotermScriptQuitCommand)
final class ScriptQuitCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            NSApplication.shared.terminate(nil)
        }
        return nil
    }
}

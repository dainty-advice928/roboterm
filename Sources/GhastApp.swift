import AppKit
import SwiftUI

@main
struct RobotermApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Self.configureGhosttyEnvironment()
    }

    var body: some Scene {
        // Window creation is handled by AppDelegate.
        // We use a hidden settings scene to satisfy the App protocol.
        Settings { EmptyView() }
    }

    /// Set up environment variables needed by libghostty before initialization.
    private static func configureGhosttyEnvironment() {
        let fm = FileManager.default

        // GHOSTTY_RESOURCES_DIR: look in bundle first, then system Ghostty.app
        if getenv("GHOSTTY_RESOURCES_DIR") == nil {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("ghostty")
            let system = "/Applications/Ghostty.app/Contents/Resources/ghostty"

            if let bundled, fm.fileExists(atPath: bundled.path) {
                setenv("GHOSTTY_RESOURCES_DIR", bundled.path, 1)
            } else if fm.fileExists(atPath: system) {
                setenv("GHOSTTY_RESOURCES_DIR", system, 1)
            }
        }

        if getenv("TERM") == nil {
            setenv("TERM", "xterm-ghostty", 1)
        }

        if getenv("TERM_PROGRAM") == nil {
            setenv("TERM_PROGRAM", "roboterm", 1)
        }

        // Set ROBOTERM env var so shells can auto-source tools
        setenv("ROBOTERM", "1", 1)

        // Point to the tools script for auto-sourcing
        if let toolsPath = Bundle.main.path(forResource: "roboterm-tools", ofType: "sh") {
            setenv("ROBOTERM_TOOLS", toolsPath, 1)
        } else {
            // Fallback: check common locations
            let paths = [
                "/Applications/ROBOTERM.app/Contents/Resources/roboterm-tools.sh",
                Bundle.main.bundlePath + "/Contents/Resources/scripts/roboterm-tools.sh",
            ]
            for path in paths where FileManager.default.fileExists(atPath: path) {
                setenv("ROBOTERM_TOOLS", path, 1)
                break
            }
        }
    }
}

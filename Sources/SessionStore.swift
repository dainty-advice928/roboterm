import Foundation

/// Persists workspace/tab state to ~/.config/roboterm/sessions.json on quit,
/// and restores it on next launch. Supports named session profiles.
@MainActor
enum SessionStore {
    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/roboterm")
    private static var sessionFile: URL { configDir.appendingPathComponent("sessions.json") }
    private static var sessionsDir: URL { configDir.appendingPathComponent("sessions") }

    // MARK: - Codable models

    struct SessionData: Codable {
        let windows: [WindowData]
    }

    struct WindowData: Codable {
        let workspaces: [WorkspaceData]
        let selectedWorkspaceIndex: Int?
        let isSidebarVisible: Bool
        // Window geometry (optional for backward compat)
        let windowX: Double?
        let windowY: Double?
        let windowWidth: Double?
        let windowHeight: Double?
    }

    struct WorkspaceData: Codable {
        let customName: String?
        let directory: String
        let tabs: [TabData]
        let splitLayout: SplitNode.Serialized?
        let selectedTabIndex: Int?
    }

    struct TabData: Codable {
        let workingDirectory: String?
        let title: String?
        let sshConfig: SSHConnectionConfig?
    }

    // MARK: - Save (auto)

    static func save(tabManagers: [TabManager]) {
        let session = buildSession(from: tabManagers)
        writeSession(session, to: sessionFile)
    }

    // MARK: - Restore (auto)

    static func restore() -> SessionData? {
        readSession(from: sessionFile)
    }

    // MARK: - Named sessions

    static func saveNamed(name: String, tabManagers: [TabManager]) {
        let session = buildSession(from: tabManagers)
        ensureDir(sessionsDir)
        let file = sessionsDir.appendingPathComponent("\(name).json")
        writeSession(session, to: file)
    }

    static func restoreNamed(name: String) -> SessionData? {
        let file = sessionsDir.appendingPathComponent("\(name).json")
        return readSession(from: file)
    }

    static func listNamedSessions() -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    // MARK: - Apply restored session

    /// Apply restored session data to the app delegate.
    /// Returns true if at least one window was restored.
    static func apply(_ session: SessionData, to delegate: AppDelegate) -> Bool {
        guard !session.windows.isEmpty else { return false }

        let hasContent = session.windows.contains { window in
            window.workspaces.contains { !$0.tabs.isEmpty }
        }
        guard hasContent else { return false }

        for windowData in session.windows {
            let tabManager = TabManager(restoring: true)
            delegate.registerTabManager(tabManager)

            for wsData in windowData.workspaces {
                guard !wsData.tabs.isEmpty else { continue }

                let ws = tabManager.createWorkspace(directory: wsData.directory)
                ws.customName = wsData.customName

                for tabData in wsData.tabs {
                    let tab = Tab(
                        workingDirectory: tabData.workingDirectory ?? wsData.directory,
                        sshConfig: tabData.sshConfig
                    )
                    if let title = tabData.title, !title.isEmpty, tabData.sshConfig == nil {
                        tab.title = title
                    }
                    ws.tabs.append(tab)
                }

                if let selIdx = wsData.selectedTabIndex, selIdx < ws.tabs.count {
                    ws.selectedTabId = ws.tabs[selIdx].id
                } else {
                    ws.selectedTabId = ws.tabs.first?.id
                }

                // Restore split layout if saved and tabs match
                if let serialized = wsData.splitLayout,
                   let layout = SplitNode.deserialize(serialized) {
                    let deserializedIds = layout.allTabIds
                    if deserializedIds.count == ws.tabs.count && deserializedIds.count > 1 {
                        // Remap deserialized tab IDs to actual restored tab IDs
                        var allRemapped = true
                        for (oldId, tab) in zip(deserializedIds, ws.tabs) {
                            if let leaf = layout.findLeaf(for: oldId) {
                                leaf.content = .tab(tab.id)
                            } else {
                                allRemapped = false
                                break
                            }
                        }
                        // Only apply layout if ALL leaves were successfully remapped
                        if allRemapped {
                            ws.splitLayout = layout
                        }
                    }
                }
            }

            if let selIdx = windowData.selectedWorkspaceIndex, selIdx < tabManager.workspaces.count {
                tabManager.selectedWorkspaceId = tabManager.workspaces[selIdx].id
            }
            tabManager.isSidebarVisible = windowData.isSidebarVisible

            delegate.createWindowForTabManager(tabManager)

            // Restore window geometry if available
            if let x = windowData.windowX, let y = windowData.windowY,
               let w = windowData.windowWidth, let h = windowData.windowHeight,
               w > 100, h > 100 {
                let frame = NSRect(x: x, y: y, width: w, height: h)
                tabManager.window?.setFrame(frame, display: true)
            }
        }

        return true
    }

    /// Delete the auto-save session file (e.g. after successful restore).
    static func clear() {
        try? FileManager.default.removeItem(at: sessionFile)
    }

    // MARK: - Helpers

    private static func buildSession(from tabManagers: [TabManager]) -> SessionData {
        let windows: [WindowData] = tabManagers.map { mgr in
            let wsData: [WorkspaceData] = mgr.workspaces.map { ws in
                let tabData: [TabData] = ws.tabs.map { tab in
                    TabData(
                        workingDirectory: tab.currentDirectory ?? tab.initialWorkingDirectory,
                        title: tab.title.isEmpty ? nil : tab.title,
                        sshConfig: tab.sshConfig
                    )
                }
                let selectedIndex: Int?
                if let selId = ws.selectedTabId {
                    selectedIndex = ws.tabs.firstIndex(where: { $0.id == selId })
                } else {
                    selectedIndex = nil
                }
                return WorkspaceData(
                    customName: ws.customName,
                    directory: ws.directory,
                    tabs: tabData,
                    splitLayout: ws.splitLayout?.serialize(),
                    selectedTabIndex: selectedIndex
                )
            }
            let selectedWsIndex: Int?
            if let selId = mgr.selectedWorkspaceId {
                selectedWsIndex = mgr.workspaces.firstIndex(where: { $0.id == selId })
            } else {
                selectedWsIndex = nil
            }
            let frame = mgr.window?.frame
            return WindowData(
                workspaces: wsData,
                selectedWorkspaceIndex: selectedWsIndex,
                isSidebarVisible: mgr.isSidebarVisible,
                windowX: frame.map { Double($0.origin.x) },
                windowY: frame.map { Double($0.origin.y) },
                windowWidth: frame.map { Double($0.size.width) },
                windowHeight: frame.map { Double($0.size.height) }
            )
        }
        return SessionData(windows: windows)
    }

    private static func writeSession(_ session: SessionData, to url: URL) {
        do {
            ensureDir(url.deletingLastPathComponent())
            let data = try JSONEncoder().encode(session)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[SessionStore] Failed to save session: \(error)")
        }
    }

    private static func readSession(from url: URL) -> SessionData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(SessionData.self, from: data)
        } catch {
            print("[SessionStore] Failed to restore session: \(error)")
            return nil
        }
    }

    private static func ensureDir(_ url: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

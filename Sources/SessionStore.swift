import Foundation

/// Persists workspace/tab state to ~/.config/roboterm/sessions.json on quit,
/// and restores it on next launch.
@MainActor
enum SessionStore {
    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/roboterm")
    private static var sessionFile: URL { configDir.appendingPathComponent("sessions.json") }

    // MARK: - Codable models

    struct SessionData: Codable {
        let windows: [WindowData]
    }

    struct WindowData: Codable {
        let workspaces: [WorkspaceData]
        let selectedWorkspaceIndex: Int?
        let isSidebarVisible: Bool
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
    }

    // MARK: - Save

    static func save(tabManagers: [TabManager]) {
        let windows: [WindowData] = tabManagers.map { mgr in
            let wsData: [WorkspaceData] = mgr.workspaces.map { ws in
                let tabData: [TabData] = ws.tabs.map { tab in
                    TabData(workingDirectory: tab.currentDirectory ?? tab.initialWorkingDirectory)
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
            return WindowData(
                workspaces: wsData,
                selectedWorkspaceIndex: selectedWsIndex,
                isSidebarVisible: mgr.isSidebarVisible
            )
        }

        let session = SessionData(windows: windows)

        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: configDir.path) {
                try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
            }
            let data = try JSONEncoder().encode(session)
            try data.write(to: sessionFile, options: .atomic)
        } catch {
            print("[SessionStore] Failed to save session: \(error)")
        }
    }

    // MARK: - Restore

    /// Attempts to restore session data from disk.  Returns nil if no session file exists.
    static func restore() -> SessionData? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionFile.path) else { return nil }

        do {
            let data = try Data(contentsOf: sessionFile)
            return try JSONDecoder().decode(SessionData.self, from: data)
        } catch {
            print("[SessionStore] Failed to restore session: \(error)")
            return nil
        }
    }

    /// Apply restored session data to the app delegate.
    /// Returns true if at least one window was restored.
    static func apply(_ session: SessionData, to delegate: AppDelegate) -> Bool {
        guard !session.windows.isEmpty else { return false }

        // Check that at least one window has workspaces with tabs
        let hasContent = session.windows.contains { window in
            window.workspaces.contains { !$0.tabs.isEmpty }
        }
        guard hasContent else { return false }

        for windowData in session.windows {
            let tabManager = TabManager(restoring: true)
            delegate.registerTabManager(tabManager)

            for (wsIndex, wsData) in windowData.workspaces.enumerated() {
                guard !wsData.tabs.isEmpty else { continue }

                let ws = tabManager.createWorkspace(directory: wsData.directory)
                ws.customName = wsData.customName

                // Remove the default tab that createWorkspace may have added
                // (createWorkspace doesn't add tabs, but just in case)
                // Actually Workspace.init doesn't create tabs — TabManager.init does via addWorkspace+createTab.
                // Since we used restoring:true, no default tab was created.

                for tabData in wsData.tabs {
                    let tab = Tab(workingDirectory: tabData.workingDirectory ?? wsData.directory)
                    ws.tabs.append(tab)
                }

                if let selIdx = wsData.selectedTabIndex, selIdx < ws.tabs.count {
                    ws.selectedTabId = ws.tabs[selIdx].id
                } else {
                    ws.selectedTabId = ws.tabs.first?.id
                }

                // We skip restoring splitLayout because the tab UUIDs are new.
                // The user will need to re-split manually.
            }

            if let selIdx = windowData.selectedWorkspaceIndex, selIdx < tabManager.workspaces.count {
                tabManager.selectedWorkspaceId = tabManager.workspaces[selIdx].id
            }
            tabManager.isSidebarVisible = windowData.isSidebarVisible

            delegate.createWindowForTabManager(tabManager)
        }

        return true
    }

    /// Delete the session file (e.g. after successful restore).
    static func clear() {
        try? FileManager.default.removeItem(at: sessionFile)
    }
}

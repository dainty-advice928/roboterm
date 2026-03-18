import AppKit
import SwiftUI

/// Main window content: sidebar + tab bar + terminal.
struct ContentView: View {
    @ObservedObject var tabManager: TabManager
    @State private var sidebarWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "sidebarWidth")
        return saved > 0 ? CGFloat(saved) : 180
    }()
    @State private var dragStartWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "sidebarWidth")
        return saved > 0 ? CGFloat(saved) : 180
    }()

    private var bgColor: Color { RF.voidBlack }

    var body: some View {
        HStack(spacing: 0) {
            if tabManager.isSidebarVisible {
                WorkspaceSidebar(tabManager: tabManager)
                    .frame(width: sidebarWidth)

                Rectangle()
                    .fill(RF.border)
                    .frame(width: 1)
                    .padding(.horizontal, 2)
                    .contentShape(Rectangle())
                    .onHover { h in
                        if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                sidebarWidth = min(max(dragStartWidth + value.translation.width, 120), 400)
                            }
                            .onEnded { _ in
                                dragStartWidth = sidebarWidth
                                UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarWidth")
                            }
                    )
            }

            VStack(spacing: 0) {
                TabBar(tabManager: tabManager)
                    .frame(height: 36)
                    .zIndex(2)
                AgentBar(tabManager: tabManager)
                    .frame(height: 28)
                    .zIndex(2)
                TerminalContainerView(tabManager: tabManager)
                    .frame(maxHeight: .infinity)
                    .clipped()
                StatusBarView(tabManager: tabManager)
                    .frame(height: 22)
                    .zIndex(2)
            }
        }
        .background(bgColor)
        .onChange(of: tabManager.isSidebarVisible) { visible in
            SidebarVisibility.shared.isVisible = visible
        }
    }
}

// MARK: - Workspace sidebar

struct WorkspaceSidebar: View {
    @ObservedObject var tabManager: TabManager

    private let sidebarBg = RF.sidebarBg

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WORKSPACES")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(RF.accent)
                    .tracking(2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // + Workspace button
            WorkspaceAddButton(tabManager: tabManager)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)

            // Divider
            Rectangle().fill(RF.accent.opacity(0.15)).frame(height: 1)
                .padding(.horizontal, 8)

            // Workspaces list — flexible, shrinks when bottom panels expand
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(tabManager.workspaces) { workspace in
                        WorkspaceItemView(
                            workspace: workspace,
                            isSelected: workspace.id == tabManager.selectedWorkspaceId,
                            onClose: { tabManager.closeWorkspace(workspace.id) },
                            onSelect: { tabManager.selectWorkspace(workspace.id) }
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)
            }
            .frame(minHeight: 60)

            // ANIMA modules section
            AnimaPanelView(tabManager: tabManager)

            // SSH connections section
            SSHPanelView(tabManager: tabManager)

            // Docker containers section — expands with scroll
            DockerPanelView(tabManager: tabManager)

            // Hardware section — same style as Docker panel
            HardwarePanelView()
        }
        .background(sidebarBg)
    }
}

struct WorkspaceAddButton: View {
    @ObservedObject var tabManager: TabManager
    @State private var isHovering = false

    var body: some View {
        Button(action: pickDirectoryAndCreate) {
            HStack(spacing: 4) {
                Text("+")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text("NEW WORKSPACE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundColor(isHovering ? RF.accent : .white.opacity(0.25))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Rectangle()
                    .stroke(isHovering ? RF.accent.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private func pickDirectoryAndCreate() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a directory for the new workspace"
        panel.directoryURL = URL(fileURLWithPath: TerminalSettings.shared.defaultWorkingDirectory)

        if panel.runModal() == .OK, let url = panel.url {
            let ws = tabManager.createWorkspace(directory: url.path)
            ws.createTab()
        }
    }
}

struct WorkspaceItemView: View {
    @ObservedObject var workspace: Workspace
    let isSelected: Bool
    let onClose: () -> Void
    let onSelect: () -> Void
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isTextFieldFocused: Bool

    /// Short directory path for display (e.g. "~/Projects/roboterm").
    private var directoryLabel: String {
        let dir = workspace.selectedTab?.currentDirectory ?? workspace.directory
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir.hasPrefix(home) {
            let rel = String(dir.dropFirst(home.count))
            return rel.isEmpty ? "~" : "~" + rel
        }
        return dir
    }

    var body: some View {
        HStack(spacing: 0) {
            // Accent indicator bar for selected workspace
            Rectangle()
                .fill(isSelected ? RF.accent : Color.clear)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                if isEditing {
                    TextField("Name", text: $editText)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            let trimmed = editText.trimmingCharacters(in: .whitespaces)
                            workspace.customName = trimmed.isEmpty ? nil : trimmed
                            isEditing = false
                            isTextFieldFocused = false
                        }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .onExitCommand {
                        isEditing = false
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(workspace.displayName.uppercased())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                            .foregroundColor(isSelected ? RF.accent : .white.opacity(0.5))

                        if let badge = workspace.badge {
                            Text(badge)
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(RF.green)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Rectangle().stroke(RF.green.opacity(0.4), lineWidth: 1))
                        }
                    }
                }

                Text(directoryLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isSelected ? .white.opacity(0.4) : .white.opacity(0.2))
            }
            .padding(.leading, 10)

            Spacer()

            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("\(workspace.tabs.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? RF.accent.opacity(0.6) : .white.opacity(0.15))
            }
        }
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            Rectangle()
                .fill(isSelected ? RF.accent.opacity(0.12) : isHovering ? Color.white.opacity(0.04) : Color.clear)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
        }
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            editText = workspace.customName ?? workspace.displayName
            isEditing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isTextFieldFocused = true }
        }
        .onTapGesture(count: 1) {
            if !isEditing { onSelect() }
        }
        .onChange(of: isTextFieldFocused) { focused in
            if !focused && isEditing {
                // Lost focus = cancel editing
                isEditing = false
            }
        }
        .contextMenu {
            Button("Rename Workspace") {
                editText = workspace.customName ?? workspace.displayName
                isEditing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isTextFieldFocused = true }
            }
            Divider()
            Button("Close Workspace") { onClose() }
        }
    }
}

// MARK: - Tab bar

struct TabBar: View {
    @ObservedObject var tabManager: TabManager

    private var bgColor: Color { Color(nsColor: TerminalSettings.shared.backgroundColor) }

    var body: some View {
        ZStack {
            // Tabs fill the entire width
            if let ws = tabManager.selectedWorkspace {
                TabListView(workspace: ws, tabManager: tabManager)
            }

            // Buttons overlay on left and right edges
            HStack(spacing: 0) {
                // Sidebar toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        tabManager.isSidebarVisible.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(tabManager.isSidebarVisible ? 0.6 : 0.3))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(bgColor)

                Spacer()

                // Split button
                Button(action: {
                    if let ws = tabManager.selectedWorkspace, let tab = ws.selectedTab {
                        ws.createSplitTab(nextTo: tab.id, direction: .horizontal)
                    }
                }) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(bgColor)

                // New tab button
                Button(action: {
                    tabManager.selectedWorkspace?.createTab()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(bgColor)
            }
        }
        .frame(height: 36)
        .background(bgColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }
}

struct TabListView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var tabManager: TabManager
    @State private var draggedTabId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                TabItemView(
                    tab: tab,
                    index: index,
                    isSelected: tab.id == workspace.selectedTabId,
                    isOnly: workspace.tabs.count == 1,
                    onClose: { tabManager.closeTab(tab.id) },
                    onDuplicate: { workspace.createTab() }
                )
                .onTapGesture { workspace.selectTab(tab.id) }
                .onDrag {
                    draggedTabId = tab.id
                    return NSItemProvider(object: tab.id.uuidString as NSString)
                } preview: {
                    Text(tab.title.isEmpty ? "Terminal" : tab.title)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(4)
                }
                .onDrop(of: [.text], delegate: TabDropDelegate(
                    targetId: tab.id,
                    workspace: workspace,
                    draggedTabId: $draggedTabId
                ))

                // Separator between tabs
                if index < workspace.tabs.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 14)
                }
            }
        }
    }
}

struct TabItemView: View {
    @ObservedObject var tab: Tab
    let index: Int
    let isSelected: Bool
    let isOnly: Bool
    let onClose: () -> Void
    var onDuplicate: (() -> Void)?
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var isRenameFocused: Bool

    private var indicatorColor: Color {
        tab.isSSH ? RF.cyan : RF.accent
    }

    var body: some View {
        HStack(spacing: 6) {
            if isHovering && !isOnly {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // SSH icon
            if tab.isSSH {
                Image(systemName: "network")
                    .font(.system(size: 10))
                    .foregroundColor(RF.cyan)
            }

            if isRenaming {
                TextField("Title", text: $renameText)
                    .focused($isRenameFocused)
                    .onSubmit {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { tab.title = trimmed }
                        isRenaming = false
                        isRenameFocused = false
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .onExitCommand {
                        isRenaming = false
                        isRenameFocused = false
                    }
            } else {
                Text(tab.title.isEmpty ? "Terminal" : tab.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .white.opacity(0.4))
            }

            if index < 9 {
                Text("\u{2318}\(index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.white.opacity(0.06) : isHovering ? Color.white.opacity(0.03) : Color.clear)
        .overlay(alignment: .bottom) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(indicatorColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onChange(of: isRenameFocused) { focused in
            if !focused && isRenaming { isRenaming = false }
        }
        .contextMenu {
            if let sshConfig = tab.sshConfig {
                Button("Reconnect") {
                    // Close this tab and open a fresh SSH connection
                    onClose()
                    AppDelegate.shared?.focusedTabManager?.createSSHTab(config: sshConfig)
                }
                Divider()
            }
            Button("Rename") {
                renameText = tab.title.isEmpty ? "Terminal" : tab.title
                isRenaming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isRenameFocused = true }
            }
            if let onDuplicate, !tab.isSSH {
                Button("Duplicate") { onDuplicate() }
            }
            Divider()
            Button("Close") { onClose() }
        }
    }
}

// MARK: - Tab drag & drop

struct TabDropDelegate: DropDelegate {
    let targetId: UUID
    let workspace: Workspace
    @Binding var draggedTabId: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedTabId = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedId = draggedTabId, draggedId != targetId else { return }
        withAnimation(.easeInOut(duration: 0.1)) {
            workspace.moveTab(from: draggedId, to: targetId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

// MARK: - Terminal container

struct TerminalContainerView: NSViewRepresentable {
    @ObservedObject var tabManager: TabManager

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let ws = tabManager.selectedWorkspace,
              let selectedTab = tabManager.selectedTab else {
            container.subviews.forEach { $0.isHidden = true }
            return
        }

        let tabLookup: (UUID) -> Tab? = { id in ws.tabs.first { $0.id == id } }

        // Clean up stale tab IDs from split layout (deferred to avoid SwiftUI re-entrancy)
        if let layout = ws.splitLayout {
            let tabIds = Set(ws.tabs.map { $0.id })
            let stale = layout.allTabIds.filter { !tabIds.contains($0) }
            if !stale.isEmpty || layout.allTabIds.count <= 1 {
                DispatchQueue.main.async {
                    for splitTabId in stale {
                        _ = layout.removeTab(splitTabId)
                    }
                    if layout.allTabIds.count <= 1 {
                        ws.splitLayout = nil
                    }
                }
            }
        }

        if let layout = ws.splitLayout,
           layout.allTabIds.count > 1,
           layout.allTabIds.contains(selectedTab.id) {
            // Split mode: show multiple tabs via SplitContainerView
            let splitContainer: SplitContainerView
            if let existing = container.subviews.compactMap({ $0 as? SplitContainerView }).first {
                splitContainer = existing
            } else {
                splitContainer = SplitContainerView(frame: container.bounds)
                splitContainer.translatesAutoresizingMaskIntoConstraints = true
                splitContainer.autoresizingMask = [.width, .height]
                container.addSubview(splitContainer)
            }

            splitContainer.isHidden = false
            splitContainer.update(with: layout, tabLookup: tabLookup)

            // Trigger redisplay for all visible panes.
            for tabId in layout.allTabIds {
                if let tab = tabLookup(tabId), let tv = tab.terminalView {
                    tv.needsDisplay = true
                }
            }
        } else {
            // Single tab mode — hide split container but don't remove it
            for subview in container.subviews where subview is SplitContainerView {
                subview.isHidden = true
            }

            let terminalView = selectedTab.makeRobotermTerminal(frame: container.bounds)

            if terminalView.superview is SplitContainerView {
                // Move out of the split container back to the main container
                terminalView.removeFromSuperview()
            }

            if terminalView.superview !== container {
                terminalView.removeFromSuperview()
                // Use autoresizingMask instead of Auto Layout to avoid
                // fighting SwiftUI's constraint system (per research findings)
                terminalView.translatesAutoresizingMaskIntoConstraints = true
                terminalView.autoresizingMask = [.width, .height]
                terminalView.frame = container.bounds
                container.addSubview(terminalView)
            }

            // Hide other direct terminal views
            for subview in container.subviews where subview is RobotermTerminal {
                subview.isHidden = (subview !== terminalView)
            }
            terminalView.isHidden = false

            terminalView.needsDisplay = true

            DispatchQueue.main.async {
                selectedTab.focus()
            }
        }
    }
}

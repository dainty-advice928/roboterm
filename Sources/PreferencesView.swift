import SwiftUI
import AppKit

// MARK: - Preferences window (4 tabs)

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            AgentsTab()
                .tabItem { Label("Agents", systemImage: "sparkles") }
            AnimaTab()
                .tabItem { Label("ANIMA", systemImage: "cpu") }
            SSHConnectionsTab()
                .tabItem { Label("SSH", systemImage: "network") }
        }
        .frame(minWidth: 640, idealWidth: 700, maxWidth: 900,
               minHeight: 500, idealHeight: 600, maxHeight: 800)
    }
}

// MARK: - General tab

struct GeneralTab: View {
    @ObservedObject private var settings = TerminalSettings.shared

    private let shells = ["/bin/zsh", "/bin/bash", "/usr/local/bin/fish", "/opt/homebrew/bin/fish"]

    var body: some View {
        Form {
            Section("Shell") {
                Picker("Default shell", selection: $settings.shell) {
                    ForEach(shells, id: \.self) { sh in
                        Text(sh).tag(sh)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Working directory")
                    Spacer()
                    Text(shortenPath(settings.defaultWorkingDirectory))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...") { pickDirectory() }
                }
            }

            Section("Session") {
                Toggle("Restore session on launch", isOn: $settings.restoreSessionOnLaunch)
                Toggle("Save session on quit", isOn: $settings.saveSessionOnQuit)
            }

            Section("ROS2") {
                Toggle("Auto-source workspace on new tab", isOn: $settings.ros2AutoSource)
                if settings.ros2AutoSource {
                    HStack {
                        Text("Workspace path")
                        Spacer()
                        TextField("~/ros2_ws", text: $settings.ros2WorkspacePath)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.shell) { _ in settings.save() }
        .onChange(of: settings.restoreSessionOnLaunch) { _ in settings.save() }
        .onChange(of: settings.saveSessionOnQuit) { _ in settings.save() }
        .onChange(of: settings.ros2AutoSource) { _ in settings.save() }
        .onChange(of: settings.ros2WorkspacePath) { _ in settings.save() }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.defaultWorkingDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultWorkingDirectory = url.path
            settings.save()
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            let rel = String(path.dropFirst(home.count))
            return rel.isEmpty ? "~" : "~" + rel
        }
        return path
    }
}

// MARK: - Appearance tab

struct AppearanceTab: View {
    @ObservedObject private var settings = TerminalSettings.shared

    /// Dynamically detect installed Nerd Font families (Mono variants only, for terminal use).
    private var nerdFonts: [String] {
        let allFamilies = NSFontManager.shared.availableFontFamilies
        let nerd = allFamilies
            .filter { $0.contains("Nerd Font") }
            .sorted()
        // If no Nerd Fonts installed, fall back to Menlo
        return nerd.isEmpty ? ["Menlo"] : nerd
    }

    var body: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: $settings.fontName) {
                    ForEach(nerdFonts, id: \.self) { font in
                        Text(font)
                            .font(.system(size: 12, design: .monospaced))
                            .tag(font)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Size")
                    Slider(value: $settings.fontSize, in: 8...24, step: 1)
                    Text("\(Int(settings.fontSize))pt")
                        .monospacedDigit()
                        .frame(width: 36)
                }
            }

            Section("Colors") {
                ColorPicker("Background", selection: bgBinding)
                ColorPicker("Foreground", selection: fgBinding)

                HStack {
                    Text("Opacity")
                    Slider(value: $settings.backgroundOpacity, in: 0.5...1.0, step: 0.05)
                    Text("\(Int(settings.backgroundOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 36)
                }
            }

            Section("Theme Presets") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                    ForEach(ThemePreset.presets) { preset in
                        ThemePresetButton(preset: preset) {
                            settings.applyTheme(preset)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.fontName) { _ in settings.save() }
        .onChange(of: settings.fontSize) { _ in settings.save() }
        .onChange(of: settings.backgroundOpacity) { _ in settings.save() }
    }

    private var bgBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.backgroundColor) },
            set: {
                settings.backgroundColor = NSColor($0)
                settings.save()
            }
        )
    }

    private var fgBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.foregroundColor) },
            set: {
                settings.foregroundColor = NSColor($0)
                settings.save()
            }
        )
    }
}

struct ThemePresetButton: View {
    let preset: ThemePreset
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: NSColor(hex: preset.background) ?? .black))
                    .frame(height: 32)
                    .overlay(
                        Text("Aa")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(nsColor: NSColor(hex: preset.foreground) ?? .white))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isHovering ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                Text(preset.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Agents tab

struct AgentsTab: View {
    @ObservedObject private var settings = TerminalSettings.shared
    @State private var selectedAgentId: UUID?

    var body: some View {
        HSplitView {
            // Agent list
            VStack(spacing: 0) {
                List(selection: $selectedAgentId) {
                    ForEach(settings.agents) { agent in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(nsColor: NSColor(hex: agent.colorHex) ?? .white))
                                .frame(width: 8, height: 8)
                            Text(agent.name)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            if !agent.enabled {
                                Text("OFF")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(agent.id)
                    }
                }
                .listStyle(.bordered)

                HStack(spacing: 4) {
                    Button(action: addAgent) {
                        Image(systemName: "plus")
                    }
                    Button(action: removeAgent) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedAgentId == nil)
                    Spacer()
                    Button("Reset Defaults") {
                        settings.agents = AgentConfig.defaultAgents
                        settings.saveAgents()
                        selectedAgentId = settings.agents.first?.id
                    }
                    .font(.system(size: 11))
                }
                .padding(6)
            }
            .frame(minWidth: 160, maxWidth: 200)

            // Agent detail editor
            if let idx = settings.agents.firstIndex(where: { $0.id == selectedAgentId }) {
                AgentDetailView(agent: $settings.agents[idx], onSave: { settings.saveAgents() })
            } else {
                VStack {
                    Spacer()
                    Text("Select an agent to edit")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(minHeight: 300)
        .onAppear {
            if selectedAgentId == nil { selectedAgentId = settings.agents.first?.id }
        }
    }

    private func addAgent() {
        let agent = AgentConfig(name: "new-agent", command: "echo", args: "hello",
                                colorHex: "#FFB800", icon: "terminal")
        settings.agents.append(agent)
        selectedAgentId = agent.id
        settings.saveAgents()
    }

    private func removeAgent() {
        guard let id = selectedAgentId else { return }
        settings.agents.removeAll { $0.id == id }
        selectedAgentId = settings.agents.first?.id
        settings.saveAgents()
    }
}

struct AgentDetailView: View {
    @Binding var agent: AgentConfig
    let onSave: () -> Void

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $agent.name)
                Toggle("Enabled", isOn: $agent.enabled)
            }

            Section("Command") {
                TextField("Command", text: $agent.command)
                TextField("Arguments", text: $agent.args)
                HStack {
                    Text("Full command:")
                        .foregroundColor(.secondary)
                    Text(agent.fullCommand)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }

            Section("Appearance") {
                TextField("Color (hex)", text: $agent.colorHex)
                TextField("Icon (SF Symbol)", text: $agent.icon)
                HStack {
                    Text("Preview:")
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: agent.colorHex) ?? .white))
                        .frame(width: 12, height: 12)
                    Image(systemName: agent.icon)
                        .foregroundColor(Color(nsColor: NSColor(hex: agent.colorHex) ?? .white))
                    Text(agent.name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: agent) { _ in onSave() }
    }
}

// MARK: - ANIMA tab

struct AnimaTab: View {
    @ObservedObject private var settings = TerminalSettings.shared
    @State private var selectedModuleId: UUID?
    @State private var newModuleName = ""

    var body: some View {
        HSplitView {
            // Module list (left)
            VStack(spacing: 0) {
                List(selection: $selectedModuleId) {
                    ForEach(settings.animaConfig.moduleConfigs) { mod in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(mod.enabled ? (mod.profile == "gpu" ? Color.purple : Color.green) : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(mod.name.uppercased())
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            Spacer()
                            if !mod.enabled {
                                Text("OFF")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(mod.profile.uppercased())
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(mod.profile == "gpu" ? .purple : .secondary)
                            }
                        }
                        .tag(mod.id)
                    }
                }
                .listStyle(.bordered)

                HStack(spacing: 4) {
                    TextField("name", text: $newModuleName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 100)
                    Button(action: addModule) {
                        Image(systemName: "plus")
                    }
                    .disabled(newModuleName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(action: removeModule) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedModuleId == nil)
                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 160, maxWidth: 200)

            // Module detail + global settings (right)
            Form {
                if let idx = settings.animaConfig.moduleConfigs.firstIndex(where: { $0.id == selectedModuleId }) {
                    AnimaModuleDetailView(
                        module: $settings.animaConfig.moduleConfigs[idx],
                        onSave: { syncAndSave() }
                    )
                } else {
                    Section("Module") {
                        Text("Select a module to configure")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Docker Compose") {
                    HStack {
                        Text("Compose path")
                        Spacer()
                        TextField("~/path/to/compose", text: $settings.animaConfig.composePath)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                }

                Section("ROS2") {
                    Picker("Distribution", selection: $settings.animaConfig.rosDistro) {
                        Text("Jazzy").tag("jazzy")
                        Text("Iron").tag("iron")
                        Text("Humble").tag("humble")
                        Text("Rolling").tag("rolling")
                    }
                    .pickerStyle(.menu)

                    Stepper("Domain ID: \(settings.animaConfig.rosDomainId)",
                            value: $settings.animaConfig.rosDomainId, in: 0...232)
                }

                Section("Behavior") {
                    Toggle("Auto-connect on launch", isOn: $settings.animaConfig.autoConnect)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minHeight: 340)
        .onAppear {
            settings.animaConfig.migrateIfNeeded()
            if selectedModuleId == nil {
                selectedModuleId = settings.animaConfig.moduleConfigs.first?.id
            }
        }
        .onChange(of: settings.animaConfig) { _ in syncAndSave() }
    }

    private func syncAndSave() {
        settings.animaConfig.modules = settings.animaConfig.moduleNames
        settings.saveAnimaConfig()
    }

    private func addModule() {
        let name = newModuleName.trimmingCharacters(in: .whitespaces).lowercased()
        // Validate: non-empty, only [a-z0-9-], no duplicates
        let validChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !name.isEmpty,
              name.unicodeScalars.allSatisfy({ validChars.contains($0) }),
              !settings.animaConfig.moduleConfigs.contains(where: { $0.name == name }) else { return }
        let mod = AnimaModuleConfig(name: name)
        settings.animaConfig.moduleConfigs.append(mod)
        selectedModuleId = mod.id
        syncAndSave()
        newModuleName = ""
    }

    private func removeModule() {
        guard let id = selectedModuleId else { return }
        settings.animaConfig.moduleConfigs.removeAll { $0.id == id }
        selectedModuleId = settings.animaConfig.moduleConfigs.first?.id
        syncAndSave()
    }
}

// MARK: - Module detail editor

struct AnimaModuleDetailView: View {
    @Binding var module: AnimaModuleConfig
    let onSave: () -> Void

    private func shellEsc(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        if s.unicodeScalars.allSatisfy({ allowed.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func pickSSHKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.directoryURL = sshDir
        if panel.runModal() == .OK, let url = panel.url {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if url.path.hasPrefix(home) {
                module.sshKeyPath = "~" + String(url.path.dropFirst(home.count))
            } else {
                module.sshKeyPath = url.path
            }
            onSave()
        }
    }

    var body: some View {
        Section("Module: \(module.name.uppercased())") {
            Toggle("Enabled", isOn: $module.enabled)

            Picker("Profile", selection: $module.profile) {
                Text("CPU").tag("cpu")
                Text("GPU").tag("gpu")
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Container name")
                Spacer()
                TextField("anima-\(module.name)", text: $module.containerName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
        }

        Section("Docker") {
            HStack {
                Text("Ports")
                Spacer()
                TextField("8080:80,9090:90", text: $module.ports)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            HStack {
                Text("Volumes")
                Spacer()
                TextField("/data/models:/models", text: $module.volumes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            HStack {
                Text("Env vars")
                Spacer()
                TextField("KEY=val,KEY2=val2", text: $module.envVars)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
        }

        Section("ROS2") {
            HStack {
                Text("Node name")
                Spacer()
                TextField("/anima/\(module.name)", text: $module.rosNodeName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            HStack {
                Text("Watched topics")
                Spacer()
                TextField("/camera/image_raw,/detections", text: $module.rosTopics)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            if !module.rosTopics.isEmpty {
                let topics = module.rosTopics.split(separator: ",").map(String.init)
                ForEach(topics, id: \.self) { topic in
                    HStack(spacing: 4) {
                        Circle().fill(Color.green.opacity(0.5)).frame(width: 6, height: 6)
                        Text(topic.trimmingCharacters(in: .whitespaces))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }

        Section("Remote Access") {
            HStack {
                Text("SSH Host")
                Spacer()
                TextField("192.168.1.110", text: $module.sshHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            HStack {
                Text("SSH User")
                Spacer()
                TextField("nvidia", text: $module.sshUser)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            HStack {
                Text("SSH Port")
                Spacer()
                TextField("22", value: $module.sshPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            HStack {
                Text("SSH Key")
                Spacer()
                TextField("~/.ssh/id_ed25519", text: $module.sshKeyPath)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Button("Browse...") { pickSSHKey() }
            }
            if !module.sshHost.isEmpty {
                Button("Connect SSH") {
                    let config = SSHConnectionConfig(
                        label: module.name.uppercased(),
                        host: module.sshHost,
                        user: module.sshUser,
                        port: module.sshPort,
                        keyPath: module.sshKeyPath
                    )
                    AppDelegate.shared?.focusedTabManager?.createSSHTab(config: config)
                }
            }
        }
    }
}

// MARK: - SSH Connections tab

struct SSHConnectionsTab: View {
    @ObservedObject private var settings = TerminalSettings.shared
    @State private var selectedConnectionId: UUID?

    var body: some View {
        HSplitView {
            // Connection list (left)
            VStack(spacing: 0) {
                List(selection: $selectedConnectionId) {
                    ForEach(settings.sshConnections) { conn in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(nsColor: NSColor(hex: conn.colorHex) ?? .cyan))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(conn.label)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                if !conn.host.isEmpty {
                                    Text("\(conn.user.isEmpty ? "" : conn.user + "@")\(conn.host)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .tag(conn.id)
                    }
                }
                .listStyle(.bordered)

                HStack(spacing: 4) {
                    Button(action: addConnection) {
                        Image(systemName: "plus")
                    }
                    Button(action: removeConnection) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedConnectionId == nil)
                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 180, maxWidth: 220)

            // Connection detail editor (right)
            if let idx = settings.sshConnections.firstIndex(where: { $0.id == selectedConnectionId }) {
                SSHConnectionDetailView(
                    connection: $settings.sshConnections[idx],
                    onSave: { settings.saveSSHConnections() }
                )
            } else {
                VStack {
                    Spacer()
                    Text("Select a connection to edit\nor click + to add one")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            }
        }
        .frame(minHeight: 340)
        .onAppear {
            if selectedConnectionId == nil { selectedConnectionId = settings.sshConnections.first?.id }
        }
    }

    private func addConnection() {
        let conn = SSHConnectionConfig()
        settings.sshConnections.append(conn)
        selectedConnectionId = conn.id
        settings.saveSSHConnections()
    }

    private func removeConnection() {
        guard let id = selectedConnectionId else { return }
        settings.sshConnections.removeAll { $0.id == id }
        selectedConnectionId = settings.sshConnections.first?.id
        settings.saveSSHConnections()
    }
}

struct SSHConnectionDetailView: View {
    @Binding var connection: SSHConnectionConfig
    let onSave: () -> Void

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Label", text: $connection.label)
                TextField("Color (hex)", text: $connection.colorHex)
                HStack {
                    Text("Preview:")
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: connection.colorHex) ?? .cyan))
                        .frame(width: 12, height: 12)
                    Image(systemName: "network")
                        .foregroundColor(Color(nsColor: NSColor(hex: connection.colorHex) ?? .cyan))
                    Text(connection.label)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }

            Section("Connection") {
                TextField("Host", text: $connection.host)
                TextField("User", text: $connection.user)
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("22", value: $connection.port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            Section("Authentication") {
                HStack {
                    TextField("~/.ssh/id_ed25519", text: $connection.keyPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") { pickKeyFile() }
                }
                switch connection.keyStatus {
                case .ok:
                    Label("Key found", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                case .missing:
                    Label("Key not found", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 11))
                case .unreadable:
                    Label("Key not readable", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 11))
                case .none:
                    EmptyView()
                }
            }

            if !connection.host.isEmpty {
                Section("Test") {
                    HStack {
                        Text("Target:")
                            .foregroundColor(.secondary)
                        let userHost = connection.user.isEmpty ? connection.host : "\(connection.user)@\(connection.host)"
                        let portStr = connection.port != 22 ? " -p \(connection.port)" : ""
                        let keyStr = connection.keyPath.isEmpty ? "" : " -i \(connection.keyPath)"
                        Text("ssh\(portStr)\(keyStr) \(userHost)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Connect Now") {
                        AppDelegate.shared?.focusedTabManager?.createSSHTab(config: connection)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: connection) { _ in onSave() }
    }

    private func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.directoryURL = sshDir
        if panel.runModal() == .OK, let url = panel.url {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if url.path.hasPrefix(home) {
                connection.keyPath = "~" + String(url.path.dropFirst(home.count))
            } else {
                connection.keyPath = url.path
            }
            onSave()
        }
    }
}

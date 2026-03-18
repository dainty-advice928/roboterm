import AppKit
import Foundation

// MARK: - Agent configuration model

struct AgentConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var args: String
    var colorHex: String
    var icon: String
    var enabled: Bool

    init(id: UUID = UUID(), name: String, command: String, args: String = "",
         colorHex: String = "#FF3B00", icon: String = "sparkles", enabled: Bool = true) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.colorHex = colorHex
        self.icon = icon
        self.enabled = enabled
    }

    /// Full command string including args.
    var fullCommand: String {
        args.isEmpty ? command : "\(command) \(args)"
    }

    static let defaultAgents: [AgentConfig] = [
        AgentConfig(name: "claude", command: "claude", args: "", colorHex: "#FF3B00", icon: "sparkles"),
        AgentConfig(name: "codex", command: "codex", args: "", colorHex: "#00FF88", icon: "gearshape"),
    ]
}

// MARK: - ANIMA module configuration

struct AnimaModuleConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var containerName: String  // Docker container name override (empty = auto: "anima-{name}")
    var profile: String        // "cpu" or "gpu"
    var enabled: Bool
    var ports: String          // e.g. "8080:80,9090:90"
    var envVars: String        // e.g. "MODEL_SIZE=large,DEBUG=1"
    var volumes: String        // e.g. "/data/models:/models"
    var rosTopics: String      // watched ROS2 topics (for sensor panel)
    var sshHost: String        // e.g. "192.168.1.110" or "jetson.local"
    var sshUser: String        // e.g. "nvidia" or "ilessio"
    var sshPort: Int           // default 22
    var sshKeyPath: String     // e.g. "~/.ssh/id_ed25519"
    var rosNodeName: String    // e.g. "/anima/azoth"

    // Custom decoding for backward compatibility — existing anima.json files
    // won't have sshHost/sshUser/sshPort/rosNodeName fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        containerName = try c.decodeIfPresent(String.self, forKey: .containerName) ?? ""
        profile = try c.decodeIfPresent(String.self, forKey: .profile) ?? "cpu"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        ports = try c.decodeIfPresent(String.self, forKey: .ports) ?? ""
        envVars = try c.decodeIfPresent(String.self, forKey: .envVars) ?? ""
        volumes = try c.decodeIfPresent(String.self, forKey: .volumes) ?? ""
        rosTopics = try c.decodeIfPresent(String.self, forKey: .rosTopics) ?? ""
        sshHost = try c.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshUser = try c.decodeIfPresent(String.self, forKey: .sshUser) ?? ""
        sshPort = try c.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshKeyPath = try c.decodeIfPresent(String.self, forKey: .sshKeyPath) ?? ""
        let node = try c.decodeIfPresent(String.self, forKey: .rosNodeName) ?? ""
        rosNodeName = node.isEmpty ? "/anima/\(name)" : node
    }

    init(id: UUID = UUID(), name: String, containerName: String = "",
         profile: String = "cpu", enabled: Bool = true,
         ports: String = "", envVars: String = "", volumes: String = "",
         rosTopics: String = "",
         sshHost: String = "", sshUser: String = "", sshPort: Int = 22,
         sshKeyPath: String = "",
         rosNodeName: String = "") {
        self.id = id
        self.name = name
        self.containerName = containerName
        self.profile = profile
        self.enabled = enabled
        self.ports = ports
        self.envVars = envVars
        self.volumes = volumes
        self.rosTopics = rosTopics
        self.sshHost = sshHost
        self.sshUser = sshUser
        self.sshPort = sshPort
        self.sshKeyPath = sshKeyPath
        self.rosNodeName = rosNodeName.isEmpty ? "/anima/\(name)" : rosNodeName
    }

    /// The Docker container name to use (falls back to "anima-{name}" if empty).
    var resolvedContainerName: String {
        containerName.isEmpty ? "anima-\(name)" : containerName
    }

    static let defaultModules: [AnimaModuleConfig] = [
        AnimaModuleConfig(name: "azoth", profile: "cpu", rosTopics: "/camera/image_raw,/detections", rosNodeName: "/anima/azoth"),
        AnimaModuleConfig(name: "chronos", profile: "cpu", rosTopics: "/tracks", rosNodeName: "/anima/chronos"),
        AnimaModuleConfig(name: "monad", profile: "gpu", rosTopics: "/reasoning/output", rosNodeName: "/anima/monad"),
        AnimaModuleConfig(name: "loci", profile: "cpu", rosTopics: "/map,/tf", rosNodeName: "/anima/loci"),
        AnimaModuleConfig(name: "osiris", profile: "cpu", rosTopics: "/diagnostics", rosNodeName: "/anima/osiris"),
        AnimaModuleConfig(name: "petra", profile: "gpu", rosTopics: "/plan,/trajectory", rosNodeName: "/anima/petra"),
    ]
}

// MARK: - SSH connection configuration

struct SSHConnectionConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var label: String       // "Jetson Orin", "Mac Mini"
    var host: String        // "192.168.1.110"
    var user: String        // "nvidia"
    var port: Int           // 22
    var keyPath: String     // "~/.ssh/id_ed25519"
    var colorHex: String    // "#00DDFF"

    init(id: UUID = UUID(), label: String = "New Host", host: String = "",
         user: String = "", port: Int = 22, keyPath: String = "",
         colorHex: String = "#00DDFF") {
        self.id = id
        self.label = label
        self.host = host
        self.user = user
        self.port = port
        self.keyPath = keyPath
        self.colorHex = colorHex
    }

    /// Status of the configured SSH key file.
    enum KeyStatus { case none, ok, missing, unreadable }

    /// Check if the configured SSH key file exists and is readable.
    var keyStatus: KeyStatus {
        guard !keyPath.isEmpty else { return .none }
        let expanded = NSString(string: keyPath).expandingTildeInPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: expanded) else { return .missing }
        guard fm.isReadableFile(atPath: expanded) else { return .unreadable }
        return .ok
    }

    /// Build the arguments array for /usr/bin/ssh.
    var sshArgs: [String] {
        var args: [String] = []
        // Prevent indefinite hangs on unreachable hosts
        args += ["-o", "ConnectTimeout=10"]
        // Detect dead connections
        args += ["-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3"]
        if port != 22 {
            args += ["-p", "\(port)"]
        }
        if !keyPath.isEmpty {
            let expanded = NSString(string: keyPath).expandingTildeInPath
            args += ["-i", expanded]
        }
        let userHost = user.isEmpty ? host : "\(user)@\(host)"
        args.append(userHost)
        return args
    }
}

// MARK: - ANIMA configuration model

struct AnimaConfig: Codable, Equatable {
    var modules: [String]  // kept for backward compatibility (derived from moduleConfigs)
    var moduleConfigs: [AnimaModuleConfig]
    var composePath: String
    var autoConnect: Bool
    var rosDistro: String
    var rosDomainId: Int

    /// Module names derived from configs (for backward compat with AnimaState.buildModuleList).
    var moduleNames: [String] {
        moduleConfigs.filter(\.enabled).map(\.name)
    }

    static let `default` = AnimaConfig(
        modules: AnimaModuleConfig.defaultModules.map(\.name),
        moduleConfigs: AnimaModuleConfig.defaultModules,
        composePath: "~/Development/AIFLOWLABS/R&D",
        autoConnect: true,
        rosDistro: "jazzy",
        rosDomainId: 0
    )

    /// Migrate from old format (just module names) to new format (full configs).
    mutating func migrateIfNeeded() {
        if moduleConfigs.isEmpty && !modules.isEmpty {
            moduleConfigs = modules.map { name in
                AnimaModuleConfig.defaultModules.first(where: { $0.name == name })
                    ?? AnimaModuleConfig(name: name)
            }
        }
        // Keep modules in sync
        modules = moduleNames
    }
}

// MARK: - Theme presets

struct ThemePreset: Identifiable {
    let id: String
    let name: String
    let background: String
    let foreground: String
    let opacity: Double

    static let presets: [ThemePreset] = [
        ThemePreset(id: "cyberpunk", name: "Industrial Cyberpunk", background: "#050505", foreground: "#FFFFFF", opacity: 1.0),
        ThemePreset(id: "dracula", name: "Dracula", background: "#282A36", foreground: "#F8F8F2", opacity: 1.0),
        ThemePreset(id: "solarized-dark", name: "Solarized Dark", background: "#002B36", foreground: "#839496", opacity: 1.0),
        ThemePreset(id: "solarized-light", name: "Solarized Light", background: "#FDF6E3", foreground: "#657B83", opacity: 1.0),
        ThemePreset(id: "monokai", name: "Monokai", background: "#272822", foreground: "#F8F8F2", opacity: 1.0),
        ThemePreset(id: "nord", name: "Nord", background: "#2E3440", foreground: "#D8DEE9", opacity: 1.0),
        ThemePreset(id: "gruvbox", name: "Gruvbox Dark", background: "#282828", foreground: "#EBDBB2", opacity: 1.0),
    ]
}

// MARK: - Terminal Settings (singleton)

/// Singleton holding terminal appearance, shell, agent, and ANIMA settings.
@MainActor
final class TerminalSettings: ObservableObject {
    static let shared = TerminalSettings()

    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/roboterm")

    // MARK: - Appearance

    @Published var backgroundColor: NSColor = NSColor(red: 0x05/255, green: 0x05/255, blue: 0x05/255, alpha: 1.0)
    @Published var foregroundColor: NSColor = .white
    @Published var fontName: String = "CaskaydiaMono Nerd Font Mono"
    @Published var fontSize: CGFloat = 13
    @Published var backgroundOpacity: Double = 1.0

    // MARK: - General

    @Published var shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    @Published var defaultWorkingDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    @Published var restoreSessionOnLaunch: Bool = true
    @Published var saveSessionOnQuit: Bool = true
    @Published var ros2AutoSource: Bool = false
    @Published var ros2WorkspacePath: String = ""

    // MARK: - Agents

    @Published var agents: [AgentConfig] = AgentConfig.defaultAgents

    // MARK: - ANIMA

    @Published var animaConfig: AnimaConfig = .default

    // MARK: - SSH Connections

    @Published var sshConnections: [SSHConnectionConfig] = []

    private init() {
        load()
    }

    // MARK: - Load

    func load() {
        let defaults = UserDefaults.standard

        // Appearance
        if let hex = defaults.string(forKey: "terminalBackgroundColor"),
           let color = NSColor(hex: hex) {
            backgroundColor = color
        }
        if let hex = defaults.string(forKey: "terminalForegroundColor"),
           let color = NSColor(hex: hex) {
            foregroundColor = color
        }
        if let name = defaults.string(forKey: "terminalFontName"), !name.isEmpty {
            // Validate font exists; fall back to first available Nerd Font or Menlo
            if NSFont(name: name, size: 13) != nil {
                fontName = name
            } else {
                let fallback = NSFontManager.shared.availableFontFamilies
                    .first { $0.contains("Nerd Font Mono") }
                    ?? "Menlo"
                fontName = fallback
            }
        }
        let size = defaults.double(forKey: "terminalFontSize")
        if size > 0 { fontSize = CGFloat(min(max(size, 8), 72)) }
        if defaults.object(forKey: "terminalBackgroundOpacity") != nil {
            backgroundOpacity = max(0.5, min(1.0, defaults.double(forKey: "terminalBackgroundOpacity")))
        }

        // General
        if let sh = defaults.string(forKey: "terminalShell"), !sh.isEmpty {
            shell = sh
        }
        if let dir = defaults.string(forKey: "defaultWorkingDirectory"), !dir.isEmpty {
            defaultWorkingDirectory = dir
        }
        if defaults.object(forKey: "restoreSessionOnLaunch") != nil {
            restoreSessionOnLaunch = defaults.bool(forKey: "restoreSessionOnLaunch")
        }
        if defaults.object(forKey: "saveSessionOnQuit") != nil {
            saveSessionOnQuit = defaults.bool(forKey: "saveSessionOnQuit")
        }
        ros2AutoSource = defaults.bool(forKey: "ros2AutoSource")
        if let wsPath = defaults.string(forKey: "ros2WorkspacePath") {
            ros2WorkspacePath = wsPath
        }

        // Agents — load from JSON file
        loadAgents()

        // ANIMA — load from JSON file
        loadAnimaConfig()

        // SSH connections — load from JSON file
        loadSSHConnections()
    }

    // MARK: - Save

    func save() {
        let defaults = UserDefaults.standard

        // Appearance
        defaults.set(backgroundColor.hexString, forKey: "terminalBackgroundColor")
        defaults.set(foregroundColor.hexString, forKey: "terminalForegroundColor")
        defaults.set(fontName, forKey: "terminalFontName")
        defaults.set(fontSize, forKey: "terminalFontSize")
        defaults.set(backgroundOpacity, forKey: "terminalBackgroundOpacity")

        // General
        defaults.set(shell, forKey: "terminalShell")
        defaults.set(defaultWorkingDirectory, forKey: "defaultWorkingDirectory")
        defaults.set(restoreSessionOnLaunch, forKey: "restoreSessionOnLaunch")
        defaults.set(saveSessionOnQuit, forKey: "saveSessionOnQuit")
        defaults.set(ros2AutoSource, forKey: "ros2AutoSource")
        defaults.set(ros2WorkspacePath, forKey: "ros2WorkspacePath")

        // Agents — save to JSON file
        saveAgents()

        // ANIMA — save to JSON file
        saveAnimaConfig()

        // SSH connections — save to JSON file
        saveSSHConnections()
    }

    // MARK: - Theme application

    func applyTheme(_ preset: ThemePreset) {
        if let bg = NSColor(hex: preset.background) { backgroundColor = bg }
        if let fg = NSColor(hex: preset.foreground) { foregroundColor = fg }
        backgroundOpacity = preset.opacity
        save()
    }

    // MARK: - Agents file I/O

    private var agentsFile: URL { Self.configDir.appendingPathComponent("agents.json") }

    private func loadAgents() {
        guard FileManager.default.fileExists(atPath: agentsFile.path),
              let data = try? Data(contentsOf: agentsFile),
              let loaded = try? JSONDecoder().decode([AgentConfig].self, from: data),
              !loaded.isEmpty else { return }
        agents = loaded
    }

    func saveAgents() {
        ensureConfigDir()
        guard let data = try? JSONEncoder().encode(agents) else { return }
        try? data.write(to: agentsFile, options: .atomic)
    }

    // MARK: - ANIMA config file I/O

    private var animaFile: URL { Self.configDir.appendingPathComponent("anima.json") }

    private func loadAnimaConfig() {
        guard FileManager.default.fileExists(atPath: animaFile.path),
              let data = try? Data(contentsOf: animaFile),
              var loaded = try? JSONDecoder().decode(AnimaConfig.self, from: data) else { return }
        // Clamp domain ID to valid range
        loaded.rosDomainId = max(0, min(232, loaded.rosDomainId))
        // Migrate old format (just names) to new format (full configs)
        loaded.migrateIfNeeded()
        animaConfig = loaded
    }

    func saveAnimaConfig() {
        ensureConfigDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(animaConfig) else { return }
        try? data.write(to: animaFile, options: .atomic)
    }

    // MARK: - SSH connections file I/O

    private var sshConnectionsFile: URL { Self.configDir.appendingPathComponent("ssh-connections.json") }

    private func loadSSHConnections() {
        guard FileManager.default.fileExists(atPath: sshConnectionsFile.path),
              let data = try? Data(contentsOf: sshConnectionsFile),
              let loaded = try? JSONDecoder().decode([SSHConnectionConfig].self, from: data),
              !loaded.isEmpty else { return }
        sshConnections = loaded
    }

    func saveSSHConnections() {
        ensureConfigDir()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(sshConnections) else { return }
        try? data.write(to: sshConnectionsFile, options: .atomic)
    }

    private func ensureConfigDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.configDir.path) {
            try? fm.createDirectory(at: Self.configDir, withIntermediateDirectories: true)
        }
    }
}

// MARK: - NSColor hex helpers

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8)  & 0xFF) / 255
        let b = CGFloat( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#050505" }
        let r = Int(c.redComponent   * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent  * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

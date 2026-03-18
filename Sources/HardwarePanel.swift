import AppKit
import SwiftUI

// MARK: - Design tokens

private let panelBg    = Color(red: 0x06/255, green: 0x06/255, blue: 0x06/255)
private let rfAccent   = Color(red: 0xFF/255, green: 0x3B/255, blue: 0x00/255)
private let rfGreen    = Color(red: 0x00/255, green: 0xFF/255, blue: 0x88/255)
private let rfCyan     = Color(red: 0x00/255, green: 0xDD/255, blue: 0xFF/255)
private let rfYellow   = Color(red: 0xFF/255, green: 0xB8/255, blue: 0x00/255)
private let rfRed      = Color(red: 0xFF/255, green: 0x33/255, blue: 0x33/255)
private let rfDim      = Color.white.opacity(0.3)

// MARK: - Device model

struct HardwareDevice: Identifiable {
    let id: String        // stable ID based on name
    let name: String
    let type: DeviceType
    var status: DeviceStatus
    let detail: String

    enum DeviceType: String, Codable {
        case camera, lidar, imu, compute, gamepad, serial
    }

    enum DeviceStatus {
        case connected, disconnected
    }

    init(name: String, type: DeviceType, status: DeviceStatus, detail: String) {
        self.id = name
        self.name = name
        self.type = type
        self.status = status
        self.detail = detail
    }
}

// MARK: - Network host config (loaded from ~/.config/roboterm/hosts.json)

struct NetworkHost: Codable {
    let name: String
    let host: String       // IP or hostname
    let type: String       // "jetson", "rpi", "server", "robot"
}

// MARK: - Hardware Panel View

struct HardwarePanel: View {
    @State private var devices: [HardwareDevice] = []
    @State private var isScanning = false

    private let scanTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Rectangle().fill(rfAccent.opacity(0.2)).frame(height: 1)
                .padding(.horizontal, 8)

            HStack {
                Text("HARDWARE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(rfAccent.opacity(0.7))
                    .tracking(1.5)
                Spacer()
                Button(action: { scanDevices() }) {
                    Image(systemName: isScanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 8))
                        .foregroundColor(rfDim)
                        .rotationEffect(.degrees(isScanning ? 360 : 0))
                        .animation(isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isScanning)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Device list
            if devices.isEmpty && !isScanning {
                HStack(spacing: 4) {
                    Text("SCANNING...")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(rfDim)
                        .tracking(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                ForEach(devices) { device in
                    DeviceRow(device: device)
                }
            }

            // Bottom status
            Rectangle().fill(rfAccent.opacity(0.1)).frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            let connectedCount = devices.filter { $0.status == .connected }.count
            HStack(spacing: 4) {
                Circle().fill(connectedCount > 0 ? rfGreen : rfDim).frame(width: 5, height: 5)
                Text(connectedCount > 0 ? "SYSTEM: ONLINE" : "SYSTEM: IDLE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(connectedCount > 0 ? rfGreen.opacity(0.6) : rfDim)
                    .tracking(0.5)
                Spacer()
                Text("\(connectedCount)/\(devices.count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(rfAccent.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(panelBg)
        .onAppear { scanDevices() }
        .onReceive(scanTimer) { _ in scanDevices() }
    }

    // MARK: - Device scanning

    private func scanDevices() {
        isScanning = true
        DispatchQueue.global(qos: .utility).async {
            let found = Self.detectDevices()

            DispatchQueue.main.async {
                // Merge: keep all previously seen devices, update their status
                var registry: [String: HardwareDevice] = [:]

                // Keep all existing devices (mark disconnected by default)
                for device in self.devices {
                    registry[device.name] = HardwareDevice(
                        name: device.name, type: device.type,
                        status: .disconnected, detail: device.detail
                    )
                }

                // Update/add found devices as connected
                for device in found {
                    registry[device.name] = HardwareDevice(
                        name: device.name, type: device.type,
                        status: .connected, detail: device.detail
                    )
                }

                // Sort: connected first, then by type, then alphabetical
                let sorted = registry.values.sorted { a, b in
                    if a.status != b.status {
                        return a.status == .connected
                    }
                    if a.type.rawValue != b.type.rawValue {
                        return a.type.rawValue < b.type.rawValue
                    }
                    return a.name < b.name
                }

                self.devices = Array(sorted)
                self.isScanning = false
            }
        }
    }

    // MARK: - Auto-detect all hardware

    static func detectDevices() -> [HardwareDevice] {
        var results: [HardwareDevice] = []

        // 1. Cameras via SPCameraDataType
        if let camOutput = runShell("system_profiler SPCameraDataType 2>/dev/null") {
            if camOutput.contains("MacBook") || camOutput.contains("FaceTime") {
                results.append(HardwareDevice(
                    name: "MacBook Camera", type: .camera, status: .connected,
                    detail: "Built-in Camera"
                ))
            }
            if camOutput.contains("iPhone") {
                results.append(HardwareDevice(
                    name: "iPhone Camera", type: .camera, status: .connected,
                    detail: "Continuity Camera"
                ))
            }
        }

        // 2. USB devices via ioreg (sandbox-safe)
        if let usbOutput = runShell("ioreg -p IOUSB -l 2>/dev/null | grep 'USB Product Name'") {
            let lines = usbOutput.components(separatedBy: "\n")

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let nameRange = trimmed.range(of: "\"USB Product Name\" = \"") else { continue }
                let afterPrefix = trimmed[nameRange.upperBound...]
                guard let endQuote = afterPrefix.firstIndex(of: "\"") else { continue }
                let productName = String(afterPrefix[..<endQuote])

                // Skip HID interfaces (they're sub-devices)
                if productName.contains("HID") { continue }
                // Skip hubs
                if productName.contains("Hub") { continue }
                // Skip monitor controls
                if productName.contains("Monitor") || productName.contains("Controls") { continue }

                // Classify the device
                let device: HardwareDevice
                if productName.contains("ZED") || productName.contains("Stereolabs") {
                    device = HardwareDevice(name: productName, type: .camera, status: .connected, detail: "Stereolabs Depth Camera")
                } else if productName.contains("RealSense") {
                    device = HardwareDevice(name: productName, type: .camera, status: .connected, detail: "Intel Depth Camera")
                } else if productName.contains("Webcam") || productName.contains("Camera") || productName.contains("Cam") {
                    device = HardwareDevice(name: productName, type: .camera, status: .connected, detail: "USB Camera")
                } else if productName.contains("Velodyne") || productName.contains("Ouster") || productName.contains("Livox") || productName.contains("RPLIDAR") || productName.contains("Hokuyo") || productName.contains("LiDAR") {
                    device = HardwareDevice(name: productName, type: .lidar, status: .connected, detail: "LiDAR Sensor")
                } else if productName.contains("IMU") || productName.contains("Bosch") || productName.contains("ICM") || productName.contains("MPU") {
                    device = HardwareDevice(name: productName, type: .imu, status: .connected, detail: "Inertial Measurement Unit")
                } else if productName.contains("Joystick") || productName.contains("Gamepad") || productName.contains("Controller") || productName.contains("Xbox") || productName.contains("DualSense") {
                    device = HardwareDevice(name: productName, type: .gamepad, status: .connected, detail: "Game Controller")
                } else {
                    // Generic USB device — still show it
                    device = HardwareDevice(name: productName, type: .serial, status: .connected, detail: "USB Device")
                }

                // Deduplicate by name
                if !results.contains(where: { $0.name == device.name }) {
                    results.append(device)
                }
            }
        }

        // 3. Serial ports
        if let serialOutput = runShell("ls /dev/tty.usb* /dev/cu.usb* 2>/dev/null") {
            for line in serialOutput.split(separator: "\n").prefix(5) {
                let name = String(line).components(separatedBy: "/").last ?? "Serial"
                if !results.contains(where: { $0.name == name }) {
                    results.append(HardwareDevice(
                        name: name, type: .serial, status: .connected, detail: String(line)
                    ))
                }
            }
        }

        // 4. Network hosts from config file (~/.config/roboterm/hosts.json)
        let hosts = loadNetworkHosts()
        for host in hosts {
            if canReachHost(host.host) {
                results.append(HardwareDevice(
                    name: host.name, type: .compute, status: .connected,
                    detail: "\(host.type) (\(host.host))"
                ))
            }
        }

        return results
    }

    // MARK: - Network hosts config

    /// Load network hosts from ~/.config/roboterm/hosts.json
    /// Format: [{"name": "JETSON", "host": "jetson.local", "type": "jetson"}, ...]
    static func loadNetworkHosts() -> [NetworkHost] {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/roboterm")
        let hostsFile = configDir.appendingPathComponent("hosts.json")

        // Create default config if it doesn't exist
        if !FileManager.default.fileExists(atPath: hostsFile.path) {
            let defaultHosts: [NetworkHost] = [
                NetworkHost(name: "JETSON", host: "jetson.local", type: "jetson"),
                NetworkHost(name: "ANIMA-MOTHER", host: "192.168.1.110", type: "server"),
            ]
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(defaultHosts) {
                try? data.write(to: hostsFile)
            }
            return defaultHosts
        }

        guard let data = try? Data(contentsOf: hostsFile),
              let hosts = try? JSONDecoder().decode([NetworkHost].self, from: data) else {
            return []
        }
        return hosts
    }

    // MARK: - Shell helpers

    private static func runShell(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)
            return (output?.isEmpty ?? true) ? nil : output
        } catch {
            return nil
        }
    }

    private static func canReachHost(_ host: String) -> Bool {
        let task = Process()
        task.launchPath = "/sbin/ping"
        task.arguments = ["-c", "1", "-W", "1000", host]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let deadline = DispatchTime.now() + .seconds(2)
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if task.isRunning { task.terminate() }
            }
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: HardwareDevice
    @State private var isHovering = false

    private var statusColor: Color {
        switch device.status {
        case .connected: return rfGreen
        case .disconnected: return rfDim
        }
    }

    private var typeIcon: String {
        switch device.type {
        case .camera: return "\u{25A3}"
        case .lidar: return "\u{25CE}"
        case .imu: return "\u{2316}"
        case .compute: return "\u{2395}"
        case .gamepad: return "\u{2318}"
        case .serial: return "\u{2192}"
        }
    }

    private var typeColor: Color {
        switch device.type {
        case .camera: return rfCyan
        case .lidar: return rfAccent
        case .imu: return rfYellow
        case .compute: return rfGreen
        case .gamepad: return Color.white.opacity(0.5)
        case .serial: return Color.white.opacity(0.4)
        }
    }

    private var deviceTypeLabel: String {
        switch device.type {
        case .camera: return "CAM"
        case .lidar: return "LDR"
        case .imu: return "IMU"
        case .compute: return "SBC"
        case .gamepad: return "JOY"
        case .serial: return "USB"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)

            Text(typeIcon)
                .font(.system(size: 9))
                .foregroundColor(device.status == .connected ? typeColor : rfDim)

            Text(device.name.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(device.status == .connected ? (isHovering ? typeColor : .white.opacity(0.6)) : rfDim)
                .lineLimit(1)

            Spacer()

            Text(deviceTypeLabel)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(device.status == .connected ? typeColor.opacity(0.5) : rfDim.opacity(0.5))
                .tracking(0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovering ? typeColor.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(device.detail)
    }
}

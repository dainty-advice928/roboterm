import AppKit
import IOKit
import IOKit.usb
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

// MARK: - Hardware state (persists across SwiftUI redraws)

@MainActor
final class HardwareState: ObservableObject {
    static let shared = HardwareState()

    @Published var devices: [HardwareDevice] = []
    @Published var isScanning = false

    private let scanQueue = DispatchQueue(label: "roboterm.hardware.scan")
    private var timer: Timer?

    private init() {
        // Start scanning immediately and every 30 seconds
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let currentDevices = self.devices

        scanQueue.async { [weak self] in
            let found = HardwarePanel.detectDevices()

            DispatchQueue.main.async {
                guard let self else { return }

                // If scan found nothing but we had devices before, keep old state
                // (scan likely failed due to timing)
                if found.isEmpty && !currentDevices.isEmpty {
                    self.isScanning = false
                    return
                }

                var registry: [String: HardwareDevice] = [:]
                for device in currentDevices {
                    registry[device.name] = HardwareDevice(
                        name: device.name, type: device.type,
                        status: .disconnected, detail: device.detail
                    )
                }
                for device in found {
                    registry[device.name] = HardwareDevice(
                        name: device.name, type: device.type,
                        status: device.status, detail: device.detail
                    )
                }
                let sorted = registry.values.sorted { a, b in
                    if a.status != b.status { return a.status == .connected }
                    if a.type.rawValue != b.type.rawValue { return a.type.rawValue < b.type.rawValue }
                    return a.name < b.name
                }

                self.devices = Array(sorted)
                self.isScanning = false
            }
        }
    }
}

// MARK: - Hardware Panel View

struct HardwarePanel: View {
    @ObservedObject private var state = HardwareState.shared

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
                Button(action: { state.scan() }) {
                    Image(systemName: state.isScanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 8))
                        .foregroundColor(rfDim)
                        .rotationEffect(.degrees(state.isScanning ? 360 : 0))
                        .animation(state.isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: state.isScanning)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Device list
            if state.devices.isEmpty && !state.isScanning {
                HStack(spacing: 4) {
                    Text("SCANNING...")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(rfDim)
                        .tracking(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                ForEach(state.devices) { device in
                    DeviceRow(device: device)
                }
            }

            // Bottom status
            Rectangle().fill(rfAccent.opacity(0.1)).frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            let connectedCount = state.devices.filter { $0.status == .connected }.count
            HStack(spacing: 4) {
                Circle().fill(connectedCount > 0 ? rfGreen : rfDim).frame(width: 5, height: 5)
                Text(connectedCount > 0 ? "SYSTEM: ONLINE" : "SYSTEM: IDLE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(connectedCount > 0 ? rfGreen.opacity(0.6) : rfDim)
                    .tracking(0.5)
                Spacer()
                Text("\(connectedCount)/\(state.devices.count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(rfAccent.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(panelBg)
    }

    // MARK: - Auto-detect all hardware

    static func detectDevices() -> [HardwareDevice] {
        var results: [HardwareDevice] = []

        // 1. Built-in camera — always present on MacBook
        #if arch(arm64)
        results.append(HardwareDevice(
            name: "MacBook Camera", type: .camera, status: .connected,
            detail: "Built-in FaceTime Camera"
        ))
        #endif

        // 2. USB devices via IOKit (no subprocess, works in sandbox)
        for productName in enumerateUSBDevices() {
            // Skip HID sub-interfaces, hubs, monitor controls
            if productName.contains("HID") || productName.contains("Hub") ||
               productName.contains("Monitor") || productName.contains("Controls") { continue }

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
                device = HardwareDevice(name: productName, type: .serial, status: .connected, detail: "USB Device")
            }

            if !results.contains(where: { $0.name == device.name }) {
                results.append(device)
            }
        }

        // 3. Serial ports via FileManager (no subprocess)
        if let devContents = try? FileManager.default.contentsOfDirectory(atPath: "/dev") {
            for entry in devContents where (entry.hasPrefix("tty.usb") || entry.hasPrefix("cu.usb")) {
                if !results.contains(where: { $0.name == entry }) {
                    results.append(HardwareDevice(
                        name: entry, type: .serial, status: .connected, detail: "/dev/\(entry)"
                    ))
                }
            }
        }

        // 4. Network hosts from config file (~/.config/roboterm/hosts.json)
        // Ping each host (skipped if scan is too slow — will be checked next cycle)
        let hosts = loadNetworkHosts()
        for host in hosts {
            // Add to results regardless — scan merge will handle status
            let reachable = canReachHost(host.host)
            results.append(HardwareDevice(
                name: host.name, type: .compute,
                status: reachable ? .connected : .disconnected,
                detail: "\(host.type) (\(host.host))"
            ))
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

    // MARK: - IOKit USB enumeration (no subprocess needed)

    private static func enumerateUSBDevices() -> [String] {
        var names: [String] = []

        // Try both IOUSBDevice (legacy) and IOUSBHostDevice (modern macOS)
        for className in ["IOUSBDevice", "IOUSBHostDevice"] {
            var iterator: io_iterator_t = 0
            let matchingDict = IOServiceMatching(className)
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
            guard result == KERN_SUCCESS else { continue }

            var device: io_object_t = IOIteratorNext(iterator)
            while device != 0 {
                if let namePtr = IORegistryEntryCreateCFProperty(device, "USB Product Name" as CFString, kCFAllocatorDefault, 0) {
                    if let name = namePtr.takeRetainedValue() as? String, !name.isEmpty {
                        if !names.contains(name) {
                            names.append(name)
                        }
                    }
                }
                IOObjectRelease(device)
                device = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        // Fallback: if IOKit returned nothing, try ioreg subprocess
        if names.isEmpty {
            if let output = runShell("ioreg -p IOUSB -l 2>/dev/null | grep 'USB Product Name'") {
                for line in output.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard let start = trimmed.range(of: "\"USB Product Name\" = \"") else { continue }
                    let rest = trimmed[start.upperBound...]
                    guard let end = rest.firstIndex(of: "\"") else { continue }
                    let name = String(rest[..<end])
                    if !name.isEmpty && !names.contains(name) {
                        names.append(name)
                    }
                }
            }
        }

        return names
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

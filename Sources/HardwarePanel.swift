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
    let id = UUID()
    let name: String
    let type: DeviceType
    let status: DeviceStatus
    let detail: String

    enum DeviceType {
        case camera, lidar, imu, compute, gamepad, serial
    }

    enum DeviceStatus {
        case connected, disconnected, error
    }
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
            if devices.isEmpty {
                HStack(spacing: 4) {
                    Circle().fill(rfDim).frame(width: 4, height: 4)
                    Text("NO DEVICES")
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
            HStack(spacing: 4) {
                Circle().fill(rfGreen).frame(width: 5, height: 5)
                Text("SYSTEM: ONLINE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(rfGreen.opacity(0.6))
                    .tracking(0.5)
                Spacer()
                Text("\(devices.filter { $0.status == .connected }.count)/\(devices.count)")
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
                // Only update if scan returned results, or if we had none before
                // This prevents flashing when scan is slow
                if !found.isEmpty || self.devices.isEmpty {
                    self.devices = found
                }
                self.isScanning = false
            }
        }
    }

    /// Detect connected hardware via system_profiler and /dev
    static func detectDevices() -> [HardwareDevice] {
        var results: [HardwareDevice] = []

        // USB devices via system_profiler
        if let usbOutput = Self.runShell("system_profiler SPUSBDataType 2>/dev/null") {
            // ZED cameras
            if usbOutput.contains("ZED") || usbOutput.contains("Stereolabs") {
                let model = usbOutput.contains("ZED 2i") ? "ZED 2i" :
                            usbOutput.contains("ZED 2") ? "ZED 2" :
                            usbOutput.contains("ZED Mini") ? "ZED Mini" :
                            usbOutput.contains("ZED X") ? "ZED X" : "ZED"
                results.append(HardwareDevice(
                    name: model, type: .camera, status: .connected,
                    detail: "Stereolabs Depth Camera"
                ))
            }

            // Intel RealSense
            if usbOutput.contains("RealSense") || usbOutput.contains("Intel(R) RealSense") {
                let model = usbOutput.contains("D435") ? "D435" :
                            usbOutput.contains("D455") ? "D455" :
                            usbOutput.contains("L515") ? "L515" :
                            usbOutput.contains("T265") ? "T265" : "RealSense"
                results.append(HardwareDevice(
                    name: "RealSense \(model)", type: .camera, status: .connected,
                    detail: "Intel Depth Camera"
                ))
            }

            // Generic webcams
            if usbOutput.contains("FaceTime") || usbOutput.contains("Webcam") || usbOutput.contains("Camera") {
                if !results.contains(where: { $0.type == .camera }) {
                    results.append(HardwareDevice(
                        name: "USB Camera", type: .camera, status: .connected,
                        detail: "Generic USB Camera"
                    ))
                }
            }

            // LiDAR sensors
            if usbOutput.contains("Velodyne") || usbOutput.contains("Ouster") || usbOutput.contains("Livox") || usbOutput.contains("RPLIDAR") || usbOutput.contains("Hokuyo") {
                let name = usbOutput.contains("Velodyne") ? "Velodyne" :
                           usbOutput.contains("Ouster") ? "Ouster" :
                           usbOutput.contains("Livox") ? "Livox" :
                           usbOutput.contains("RPLIDAR") ? "RPLIDAR" : "Hokuyo"
                results.append(HardwareDevice(
                    name: name, type: .lidar, status: .connected,
                    detail: "LiDAR Sensor"
                ))
            }

            // IMU
            if usbOutput.contains("IMU") || usbOutput.contains("Bosch") || usbOutput.contains("MPU") || usbOutput.contains("ICM") {
                results.append(HardwareDevice(
                    name: "IMU", type: .imu, status: .connected,
                    detail: "Inertial Measurement Unit"
                ))
            }

            // Gamepad/Joystick
            if usbOutput.contains("Joystick") || usbOutput.contains("Gamepad") || usbOutput.contains("Controller") || usbOutput.contains("Xbox") || usbOutput.contains("DualSense") || usbOutput.contains("Pro Controller") {
                results.append(HardwareDevice(
                    name: "Gamepad", type: .gamepad, status: .connected,
                    detail: "Game Controller"
                ))
            }
        }

        // Serial devices
        if let serialOutput = Self.runShell("ls /dev/tty.usb* /dev/cu.usb* 2>/dev/null") {
            let lines = serialOutput.split(separator: "\n")
            for line in lines.prefix(3) {
                let name = String(line).components(separatedBy: "/").last ?? "Serial"
                results.append(HardwareDevice(
                    name: name, type: .serial, status: .connected,
                    detail: String(line)
                ))
            }
        }

        // Check for Jetson via SSH/mDNS (quick check)
        if Self.canReachHost("jetson.local") || Self.canReachHost("192.168.1.100") {
            results.append(HardwareDevice(
                name: "JETSON", type: .compute, status: .connected,
                detail: "NVIDIA Jetson (network)"
            ))
        }

        // Check for Raspberry Pi
        if Self.canReachHost("raspberrypi.local") {
            results.append(HardwareDevice(
                name: "RPI", type: .compute, status: .connected,
                detail: "Raspberry Pi (network)"
            ))
        }

        // Check for ANIMA Mac Mini
        if Self.canReachHost("192.168.1.110") {
            results.append(HardwareDevice(
                name: "ANIMA-MOTHER", type: .compute, status: .connected,
                detail: "Mac Mini M4 Pro (192.168.1.110)"
            ))
        }

        return results
    }

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
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func canReachHost(_ host: String) -> Bool {
        // Quick ping with 1s timeout
        let task = Process()
        task.launchPath = "/sbin/ping"
        task.arguments = ["-c", "1", "-W", "1000", host]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            // Set a watchdog timer — kill if it takes too long
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
        case .error: return rfRed
        }
    }

    private var typeIcon: String {
        switch device.type {
        case .camera: return "\u{25A3}"    // filled square with inner square
        case .lidar: return "\u{25CE}"     // bullseye
        case .imu: return "\u{2316}"       // position indicator
        case .compute: return "\u{2395}"   // APL quad
        case .gamepad: return "\u{2318}"   // command key
        case .serial: return "\u{2192}"    // arrow
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

    var body: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)

            // Type icon
            Text(typeIcon)
                .font(.system(size: 9))
                .foregroundColor(typeColor)

            // Name
            Text(device.name.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(isHovering ? typeColor : .white.opacity(0.6))
                .lineLimit(1)

            Spacer()

            // Type label
            Text(deviceTypeLabel)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(typeColor.opacity(0.5))
                .tracking(0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovering ? typeColor.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(device.detail)
    }

    private var deviceTypeLabel: String {
        switch device.type {
        case .camera: return "CAM"
        case .lidar: return "LDR"
        case .imu: return "IMU"
        case .compute: return "SBC"
        case .gamepad: return "JOY"
        case .serial: return "SER"
        }
    }
}

import SwiftUI
import AppKit

@main
struct PulseApp: App {
    @StateObject private var monitor = Monitor()

    init() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnostics.run()
            exit(0)
        }
    }

    var body: some Scene {
        Window("Pulse · 系统监控", id: "dashboard") {
            Dashboard().environmentObject(monitor)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1180, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button(monitor.paused ? "继续监控" : "暂停监控") { monitor.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("导出最近历史…") { exportHistory(monitor.history) }
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
        MenuBarExtra {
            MenuPanel().environmentObject(monitor).preferredColorScheme(.dark)
        } label: {
            Image(systemName: "waveform.path.ecg")
            Text(monitor.paused ? "暂停" : Format.percent(monitor.frame.cpu))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuPanel: View {
    @EnvironmentObject var monitor: Monitor
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Pulse", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                Text(monitor.paused ? "已暂停" : "实时").foregroundStyle(Palette.mint).font(.caption)
            }
            menuRow("CPU", Format.percent(monitor.frame.cpu), Palette.blue)
            menuRow("内存", monitor.frame.memory.map(Format.bytes) ?? "—", Palette.purple)
            menuRow("下载", Format.rate(monitor.frame.download), Palette.mint)
            Divider()
            Button("打开监控面板") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
                .buttonStyle(.borderedProminent).tint(Palette.blue)
            HStack {
                Button(monitor.paused ? "继续" : "暂停") { monitor.togglePause() }
                Spacer()
                Button("退出 Pulse") { NSApp.terminate(nil) }
            }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 280)
    }
    func menuRow(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack { Circle().fill(color).frame(width: 6, height: 6); Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
    }
}

func exportHistory(_ history: [Frame]) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "Pulse-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-" )).csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    func raw(_ value: Double?) -> String { value.map { String(format: "%.4f", $0) } ?? "" }
    let formatter = ISO8601DateFormatter()
    let rows = history.map { frame in
        [formatter.string(from: frame.date), raw(frame.cpu.map { $0 * 100 }), raw(frame.memory), raw(frame.download), raw(frame.upload), raw(frame.battery.map { $0 * 100 })].joined(separator: ",")
    }
    do {
        try (["time,cpu_percent,memory_bytes,download_bytes_per_second,upload_bytes_per_second,battery_percent"] + rows).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    } catch {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

enum Diagnostics {
    static func run() {
        let load = Process()
        load.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        load.standardOutput = FileHandle.nullDevice
        load.standardError = FileHandle.nullDevice
        do { try load.run() } catch { fputs("Could not start CPU calibration process\n", stderr); exit(1) }
        defer { if load.isRunning { load.terminate(); load.waitUntilExit() } }
        let sampler = Sampler()
        _ = sampler.sample()
        _ = sampler.processes()
        Thread.sleep(forTimeInterval: 1.1)
        let frame = sampler.sample()
        let apps = sampler.processes()
        let validCPU = frame.cpu.map { (0...1).contains($0) } ?? false
        let validMemory = frame.memory.map { $0 > 0 && $0 <= frame.totalMemory } ?? false
        let validDisk = frame.diskTotal > 0 && frame.diskFree >= 0 && frame.diskFree <= frame.diskTotal
        let validNetwork = frame.download.map { $0 >= 0 } ?? (frame.interface == "未连接")
        let validApps = !apps.isEmpty && apps.allSatisfy { $0.bytes >= 0 && ($0.cpu.map { $0 >= 0 } ?? true) }
        // A single busy worker should report approximately one CPU, not a value
        // 24–42x too small from interpreting Apple Silicon Mach ticks as ns.
        let calibratedCPU = apps.first { $0.id == load.processIdentifier }?.cpu ?? -1
        let calibrated = calibratedCPU > 0.25 && calibratedCPU < 1.5
        let report: [String: Any] = [
            "passed": validCPU && validMemory && validDisk && validNetwork && validApps && calibrated,
            "calibrationWorkerCPUPercent": calibratedCPU * 100,
            "cpuPercent": (frame.cpu ?? -1) * 100,
            "logicalCores": frame.cores.count,
            "memoryUsedBytes": frame.memory ?? -1,
            "memoryTotalBytes": frame.totalMemory,
            "pressureLevel": frame.pressure ?? -1,
            "diskTotalBytes": frame.diskTotal,
            "diskFreeBytes": frame.diskFree,
            "downloadBytesPerSecond": frame.download ?? -1,
            "uploadBytesPerSecond": frame.upload ?? -1,
            "interface": frame.interface,
            "batteryPercent": frame.battery.map { $0 * 100 } ?? -1,
            "processCount": apps.count,
            "checks": ["cpu": validCPU, "memory": validMemory, "disk": validDisk, "network": validNetwork, "processes": validApps, "processCPUCalibration": calibrated]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
        if !(validCPU && validMemory && validDisk && validNetwork && validApps && calibrated) {
            if load.isRunning { load.terminate(); load.waitUntilExit() }
            exit(1)
        }
    }
}

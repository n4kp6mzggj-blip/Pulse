import Foundation
import Darwin
import IOKit.ps
import SystemConfiguration

struct Frame {
    var date = Date()
    var cpu: Double? = nil
    var cores: [Double] = []
    var memory: Double? = nil
    var totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
    var wired: Double = 0
    var compressed: Double = 0
    var cache: Double = 0
    var swap: Double = 0
    var pressure: Int? = nil
    var diskTotal: Double = 0
    var diskFree: Double = 0
    var download: Double? = nil
    var upload: Double? = nil
    var interface = "—"
    var address = "—"
    var sessionDown: Double = 0
    var sessionUp: Double = 0
    var battery: Double? = nil
    var pluggedIn = false
    var charging = false
    var batteryMinutes: Int? = nil
    var thermal = ProcessInfo.ThermalState.nominal
}

struct AppUsage: Identifiable {
    let id: Int32
    let name: String
    let bytes: Double
    let cpu: Double?
}

enum Format {
    static func bytes(_ value: Double) -> String {
        if value < 1 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .binary)
    }
    static func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return bytes(value) + "/s"
    }
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f", value * 100) + "%"
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds)) / 60
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分钟"
    }
}

// CPU/memory calculation adapted from exelban/Stats (MIT).
// See THIRD_PARTY_NOTICES.md for attribution and the full license.
final class Sampler {
    private var previousTicks: [UInt32] = []
    private var previousNetwork: [String: (UInt64, UInt64)] = [:]
    private var previousTime: TimeInterval?
    private var sessionDown: Double = 0
    private var sessionUp: Double = 0
    private var processTimes: [Int32: (UInt64, TimeInterval)] = [:]
    private let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()
    private var disks: (Double, Double) = (0, 0)
    private var diskTime: TimeInterval = 0

    func sample() -> Frame {
        var frame = Frame()
        let now = ProcessInfo.processInfo.systemUptime
        frame.thermal = ProcessInfo.processInfo.thermalState
        readCPU(&frame)
        readMemory(&frame)
        readNetwork(&frame, now: now)
        if now - diskTime > 15 || diskTime == 0 {
            // /System/Volumes/Data is the writable startup volume on modern macOS.
            let url = URL(fileURLWithPath: "/System/Volumes/Data")
            if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
               let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity {
                disks = (Double(total), Double(free))
            }
            diskTime = now
        }
        frame.diskTotal = disks.0
        frame.diskFree = disks.1
        readBattery(&frame)
        return frame
    }

    private func readCPU(_ frame: inout Frame) {
        var count: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &count) == KERN_SUCCESS,
              let info else { return }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride)) }
        let ticks = (0..<Int(count)).map { UInt32(bitPattern: info[$0]) }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return }
        var totalBusy: Double = 0
        var totalTicks: Double = 0
        for core in 0..<Int(cpuCount) {
            let base = core * Int(CPU_STATE_MAX)
            let deltas = (0..<Int(CPU_STATE_MAX)).map { Double(ticks[base + $0] &- previousTicks[base + $0]) }
            let total = deltas.reduce(0, +)
            let busy = total - deltas[Int(CPU_STATE_IDLE)]
            frame.cores.append(total > 0 ? min(1, max(0, busy / total)) : 0)
            totalBusy += busy
            totalTicks += total
        }
        if totalTicks > 0 { frame.cpu = min(1, max(0, totalBusy / totalTicks)) }
    }

    private func readMemory(_ frame: inout Frame) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let page = Double(vm_page_size)
            frame.wired = Double(stats.wire_count) * page
            frame.compressed = Double(stats.compressor_page_count) * page
            frame.cache = (Double(stats.purgeable_count) + Double(stats.external_page_count)) * page
            let used = (Double(stats.active_count) + Double(stats.inactive_count) + Double(stats.speculative_count)) * page
                + frame.wired + frame.compressed - frame.cache
            frame.memory = min(frame.totalMemory, max(0, used))
        }
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0 {
            frame.pressure = Int(pressure)
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 { frame.swap = Double(swap.xsu_used) }
    }

    private func readNetwork(_ frame: inout Frame, now: TimeInterval) {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return }
        defer { freeifaddrs(first) }
        var counters: [String: (UInt64, UInt64)] = [:]
        var addresses: [String: String] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let entry = item.pointee
            let name = String(cString: entry.ifa_name)
            guard entry.ifa_flags & UInt32(IFF_UP) != 0,
                  entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0, let address = entry.ifa_addr else { continue }
            if address.pointee.sa_family == UInt8(AF_LINK), let data = entry.ifa_data {
                let metrics = data.assumingMemoryBound(to: if_data.self).pointee
                counters[name] = (UInt64(metrics.ifi_ibytes), UInt64(metrics.ifi_obytes))
            }
            if address.pointee.sa_family == UInt8(AF_INET) {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    addresses[name] = String(cString: buffer)
                }
            }
        }
        let primary = (SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any])?["PrimaryInterface"] as? String
        // Count physical Ethernet/Wi-Fi links only: VPN/tunnel counters would duplicate traffic.
        let physical = counters.keys.filter { $0.hasPrefix("en") }
        let selected = primary.flatMap { physical.contains($0) ? $0 : nil }
            ?? physical.sorted().first(where: { addresses[$0] != nil })
        frame.interface = selected ?? "未连接"
        frame.address = selected.flatMap { addresses[$0] } ?? "—"
        if let previousTime, now > previousTime {
            var down: Double = 0
            var up: Double = 0
            for name in physical {
                guard let current = counters[name], let previous = previousNetwork[name] else { continue }
                // if_data exposes 32-bit byte counters; wrapping subtraction handles rollover.
                down += Double(UInt32(truncatingIfNeeded: current.0) &- UInt32(truncatingIfNeeded: previous.0))
                up += Double(UInt32(truncatingIfNeeded: current.1) &- UInt32(truncatingIfNeeded: previous.1))
            }
            if !physical.isEmpty {
                frame.download = down / (now - previousTime)
                frame.upload = up / (now - previousTime)
                sessionDown += down
                sessionUp += up
            }
        }
        frame.sessionDown = sessionDown
        frame.sessionUp = sessionUp
        previousNetwork = counters
        previousTime = now
    }

    private func readBattery(_ frame: inout Frame) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { continue }
            frame.battery = current / maximum
            frame.pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            frame.charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let key = frame.charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = description[key] as? Int, minutes > 0 { frame.batteryMinutes = minutes }
            break
        }
    }

    func processes() -> [AppUsage] {
        let capacity = proc_listallpids(nil, 0) + 128
        guard capacity > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(capacity))
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        let now = ProcessInfo.processInfo.systemUptime
        var nextTimes: [Int32: (UInt64, TimeInterval)] = [:]
        var result: [AppUsage] = []
        for pid in pids.prefix(min(Int(count), pids.count)) where pid > 0 {
            var task = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, size) == size else { continue }
            var name = [CChar](repeating: 0, count: 1024)
            guard proc_name(pid, &name, UInt32(name.count)) > 0 else { continue }
            let time = task.pti_total_user &+ task.pti_total_system
            var cpu: Double?
            if let previous = processTimes[pid], now > previous.1, time >= previous.0 {
                cpu = Double(time - previous.0) * secondsPerTick / (now - previous.1)
            }
            nextTimes[pid] = (time, now)
            result.append(AppUsage(id: pid, name: String(cString: name), bytes: Double(task.pti_resident_size), cpu: cpu))
        }
        processTimes = nextTimes
        return result.sorted { $0.bytes > $1.bytes }
    }
}

final class Monitor: ObservableObject {
    @Published var frame = Frame()
    @Published var history: [Frame] = []
    @Published var processes: [AppUsage] = []
    @Published var paused = false
    @Published var interval: Double = UserDefaults.standard.double(forKey: "interval") == 0 ? 2 : UserDefaults.standard.double(forKey: "interval")
    @Published var historyMinutes: Double = 5
    let chip: String
    let model: String
    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "app.pulse.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastProcesses: TimeInterval = 0

    init() {
        func sysString(_ name: String) -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "Mac" }
            return String(cString: buffer)
        }
        chip = sysString("machdep.cpu.brand_string")
        model = sysString("hw.model")
        start()
    }

    func start() {
        timer?.cancel()
        guard !paused else { return }
        UserDefaults.standard.set(interval, forKey: "interval")
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(150))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let frame = self.sampler.sample()
            var apps: [AppUsage]?
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastProcesses >= 8 || self.lastProcesses == 0 {
                apps = self.sampler.processes()
                self.lastProcesses = now
            }
            DispatchQueue.main.async {
                guard !self.paused else { return }
                self.frame = frame
                self.history.append(frame)
                self.history.removeAll { $0.date < Date().addingTimeInterval(-900) }
                if let apps { self.processes = apps }
            }
        }
        timer = source
        source.resume()
    }

    func togglePause() { paused.toggle(); start() }
    var visibleHistory: [Frame] { history.filter { $0.date >= frame.date.addingTimeInterval(-historyMinutes * 60) } }
    var pressureText: String {
        switch frame.pressure { case 1: return "正常"; case 2: return "偏高"; case 4: return "紧张"; default: return "未知" }
    }
    var thermalText: String {
        switch frame.thermal { case .nominal: return "正常"; case .fair: return "温暖"; case .serious: return "较热"; case .critical: return "过热"; @unknown default: return "未知" }
    }
}

import Darwin
import Foundation
import Combine
import IOKit.ps

/// High-performance, low-overhead hardware monitor for Apple Silicon MacBooks.
/// Reads host CPU load, VM memory usage, and IOKit power source status directly via Mach/IOKit calls.
@MainActor
final class SystemMonitorService: ObservableObject {

    @Published private(set) var cpuUsage: Double = 0.0          // 0.0 ... 100.0%
    @Published private(set) var memoryUsage: Double = 0.0       // 0.0 ... 1.0 (ratio)
    @Published private(set) var memoryUsedGB: Double = 0.0      // e.g. 9.8 GB
    @Published private(set) var memoryTotalGB: Double = 0.0     // e.g. 16.0 GB
    @Published private(set) var batteryLevel: Int = 100         // 0 ... 100%
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var hasBattery: Bool = true

    private var prevCpuTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var ticker: AnyCancellable?

    init() {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        self.memoryTotalGB = Double(totalBytes) / 1_073_741_824.0

        sample()
        start()
    }

    func start() {
        guard ticker == nil else { return }
        // 2-second interval ensures negligible CPU wakeups (< 0.01% CPU)
        ticker = Timer.publish(every: 2.0, tolerance: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sample()
            }
    }

    func stop() {
        ticker = nil
    }

    func sample() {
        updateCPU()
        updateMemory()
        updateBattery()
    }

    // MARK: - CPU Load (host_statistics)

    private func updateCPU() {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let kr = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard kr == KERN_SUCCESS else { return }

        let currentTicks = (
            user: cpuInfo.cpu_ticks.0,
            system: cpuInfo.cpu_ticks.1,
            idle: cpuInfo.cpu_ticks.2,
            nice: cpuInfo.cpu_ticks.3
        )

        if let prev = prevCpuTicks {
            let userDelta = Double(currentTicks.user - prev.user)
            let systemDelta = Double(currentTicks.system - prev.system)
            let idleDelta = Double(currentTicks.idle - prev.idle)
            let niceDelta = Double(currentTicks.nice - prev.nice)

            let totalTicks = userDelta + systemDelta + idleDelta + niceDelta
            if totalTicks > 0 {
                let load = (userDelta + systemDelta + niceDelta) / totalTicks * 100.0
                self.cpuUsage = min(max(load, 0.0), 100.0)
            }
        }
        self.prevCpuTicks = currentTicks
    }

    // MARK: - RAM (host_statistics64)

    private func updateMemory() {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard kr == KERN_SUCCESS else { return }

        let pageSize = vm_kernel_page_size
        let active = UInt64(vmStats.active_count) * UInt64(pageSize)
        let wired = UInt64(vmStats.wire_count) * UInt64(pageSize)
        let compressed = UInt64(vmStats.compressor_page_count) * UInt64(pageSize)

        let usedBytes = active + wired + compressed
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        let usedGB = Double(usedBytes) / 1_073_741_824.0
        let ratio = totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0.0

        self.memoryUsedGB = usedGB
        self.memoryUsage = min(max(ratio, 0.0), 1.0)
    }

    // MARK: - Battery (IOKit Power Sources)

    private func updateBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            self.hasBattery = false
            self.batteryLevel = 100
            self.isCharging = true
            return
        }

        var foundBattery = false
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any] {
                let isPresent = desc[kIOPSIsPresentKey] as? Bool ?? true
                guard isPresent else { continue }

                foundBattery = true
                let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
                let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
                self.batteryLevel = maxCap > 0 ? Int((Double(current) / Double(maxCap)) * 100) : current
                self.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                break
            }
        }

        self.hasBattery = foundBattery
    }
}

//
//  SystemMonitorService.swift
//  JARVIS
//
//  Reads real machine statistics: processor ticks from
//  host_processor_info, memory from host_statistics64, disk usage from
//  the file system attributes of the startup volume, and network
//  throughput from getifaddrs counters. Values are sampled on a timer
//  and published for the dashboard status widget.
//

import Foundation
import Darwin
import os

// MARK: - Sampler

/// Raw processor tick counters for every core.
struct ProcessorTicks: Sendable {
    /// Ticks spent in user space per core.
    var user: [UInt64] = []
    /// Ticks spent in system calls per core.
    var system: [UInt64] = []
    /// Idle ticks per core.
    var idle: [UInt64] = []
    /// Ticks spent on low priority work per core.
    var nice: [UInt64] = []

    /// Number of cores captured.
    var coreCount: Int { user.count }

    /// Total busy ticks across all cores.
    var busyTicks: UInt64 {
        zip(user, system).reduce(UInt64(0)) { partial, pair in
            partial + pair.0 + pair.1
        } + nice.reduce(0, +)
    }

    /// Total ticks including idle time.
    var totalTicks: UInt64 {
        busyTicks + idle.reduce(0, +)
    }
}

/// Network byte counters keyed by interface name.
struct NetworkCounters: Sendable {
    /// Bytes received per interface.
    var received: [String: UInt64] = [:]
    /// Bytes sent per interface.
    var sent: [String: UInt64] = [:]
}

/// Samples machine statistics and turns them into `SystemMetrics`.
final class SystemMetricsSampler {

    private var previousTicks: ProcessorTicks?
    private var previousNetwork: NetworkCounters?
    private var previousNetworkDate: Date?

    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Monitor")

    /// Captures one sample, using the previous sample to compute rates.
    func sample() -> SystemMetrics {
        let ticks = Self.captureProcessorTicks()
        let usage = Self.processorUsage(previous: previousTicks, current: ticks)
        previousTicks = ticks

        let memory = Self.memoryUsage()
        let disk = Self.diskUsage()

        let network = Self.networkCounters()
        let now = Date()
        var download: Double = 0
        var upload: Double = 0
        if let previousNetwork, let previousNetworkDate {
            let elapsed = max(0.5, now.timeIntervalSince(previousNetworkDate))
            let receivedDelta = Self.total(network.received) > Self.total(previousNetwork.received)
                ? Self.total(network.received) - Self.total(previousNetwork.received)
                : 0
            let sentDelta = Self.total(network.sent) > Self.total(previousNetwork.sent)
                ? Self.total(network.sent) - Self.total(previousNetwork.sent)
                : 0
            download = Double(receivedDelta) / elapsed
            upload = Double(sentDelta) / elapsed
        }
        previousNetwork = network
        previousNetworkDate = now

        return SystemMetrics(
            processorUsage: usage,
            processorCount: ProcessInfo.processInfo.processorCount,
            memoryUsedBytes: memory.used,
            memoryTotalBytes: memory.total,
            diskUsedBytes: disk.used,
            diskTotalBytes: disk.total,
            downloadBytesPerSecond: download,
            uploadBytesPerSecond: upload,
            networkInterfaceName: networkBusiestInterface(),
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            sampledAt: now
        )
    }

    /// Name of the interface carrying traffic, for the status caption.
    private func networkBusiestInterface() -> String {
        let addresses = Self.interfaceAddresses()
        if let primary = addresses.first(where: { $0.hasPrefix("en") }) {
            return primary
        }
        return addresses.first ?? "none"
    }

    // MARK: - Processor

    /// Reads per core tick counters.
    static func captureProcessorTicks() -> ProcessorTicks? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else {
            return nil
        }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            let address = vm_address_t(UInt(bitPattern: UnsafeMutableRawPointer(info)))
            vm_deallocate(mach_task_self_, address, size)
        }

        var ticks = ProcessorTicks()
        let statesPerCore = Int(CPU_STATE_MAX)
        for core in 0..<Int(cpuCount) {
            let base = core * statesPerCore
            ticks.user.append(UInt64(info[base + Int(CPU_STATE_USER)]))
            ticks.system.append(UInt64(info[base + Int(CPU_STATE_SYSTEM)]))
            ticks.idle.append(UInt64(info[base + Int(CPU_STATE_IDLE)]))
            ticks.nice.append(UInt64(info[base + Int(CPU_STATE_NICE)]))
        }
        return ticks
    }

    /// Computes usage between two samples, 0 to 1.
    static func processorUsage(previous: ProcessorTicks?, current: ProcessorTicks?) -> Double {
        guard let current, let previous, previous.coreCount == current.coreCount else {
            return 0
        }
        let busyDelta = current.busyTicks >= previous.busyTicks
            ? current.busyTicks - previous.busyTicks
            : 0
        let totalDelta = current.totalTicks >= previous.totalTicks
            ? current.totalTicks - previous.totalTicks
            : 0
        guard totalDelta > 0 else { return 0 }
        return min(max(Double(busyDelta) / Double(totalDelta), 0), 1)
    }

    // MARK: - Memory

    /// Resident memory in use, using the same accounting Activity Monitor
    /// reports for the memory pressure readout.
    static func memoryUsage() -> (used: UInt64, total: UInt64) {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &statistics) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return (0, total)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(statistics.active_count) * pageSize
        let wired = UInt64(statistics.wire_count) * pageSize
        let compressed = UInt64(statistics.compressor_page_count) * pageSize
        let used = min(active + wired + compressed, total)
        return (used, total)
    }

    // MARK: - Disk

    /// Used and total bytes on the startup volume.
    static func diskUsage() -> (used: Int64, total: Int64) {
        let path = NSHomeDirectory()
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let total = (attributes[.systemSize] as? NSNumber)?.int64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value,
              total > 0 else {
            return (0, 0)
        }
        return (max(0, total - free), total)
    }

    // MARK: - Network

    /// Cumulative byte counters for every physical interface.
    static func networkCounters() -> NetworkCounters {
        var counters = NetworkCounters()
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let first = addressPointer else {
            return counters
        }
        defer { freeifaddrs(addressPointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            let entry = interface.pointee
            let name = String(cString: entry.ifa_name)

            if !name.hasPrefix("lo"), let address = entry.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let data = entry.ifa_data {
                let interfaceData = data.assumingMemoryBound(to: if_data.self).pointee
                counters.received[name] = UInt64(interfaceData.ifi_ibytes)
                counters.sent[name] = UInt64(interfaceData.ifi_obytes)
            }

            cursor = entry.ifa_next
        }
        return counters
    }

    /// Names of the interfaces that are up.
    static func interfaceAddresses() -> [String] {
        var names: [String] = []
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let first = addressPointer else {
            return names
        }
        defer { freeifaddrs(addressPointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            let entry = interface.pointee
            let name = String(cString: entry.ifa_name)
            let isUp = (entry.ifa_flags & UInt32(IFF_UP)) != 0
            let isLoopback = (entry.ifa_flags & UInt32(IFF_LOOPBACK)) != 0
            if isUp, !isLoopback, !names.contains(name) {
                names.append(name)
            }
            cursor = entry.ifa_next
        }
        return names
    }

    private static func total(_ values: [String: UInt64]) -> UInt64 {
        values.values.reduce(0, +)
    }
}

// MARK: - Service

/// Publishes machine statistics for the dashboard.
@MainActor
@Observable
final class SystemMonitorService {

    /// Most recent sample.
    private(set) var metrics: SystemMetrics = .placeholder

    /// True while the sampling loop is running.
    private(set) var isMonitoring = false

    /// How often a sample is taken.
    private(set) var interval: TimeInterval

    private let sampler = SystemMetricsSampler()
    private var samplingTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.jarvis.desktop", category: "Monitor")

    init(interval: TimeInterval = 3) {
        self.interval = interval
    }

    /// Starts periodic sampling. Calling this twice restarts the loop.
    func start(interval: TimeInterval? = nil) {
        if let interval {
            self.interval = max(1, interval)
        }
        stop()
        isMonitoring = true

        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                _ = self.refreshNow()
                let nanoseconds = UInt64(max(1, self.interval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    /// Stops periodic sampling.
    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        isMonitoring = false
    }

    /// Takes one sample immediately and publishes it.
    ///
    /// Sampling allocates a few pages, deallocates them, and reads counters,
    /// which takes well under a millisecond, so it is safe on the main actor.
    @discardableResult
    func refreshNow() -> SystemMetrics {
        let sample = sampler.sample()
        metrics = sample
        return sample
    }

    /// Short summary line used by the assistant when reporting status.
    var summaryText: String {
        let cpu = "\(Int((metrics.processorUsage * 100).rounded())) percent processor"
        let memory = "\(SystemMetrics.formatBytes(Int64(metrics.memoryUsedBytes))) of \(SystemMetrics.formatBytes(Int64(metrics.memoryTotalBytes))) memory used"
        let disk = "\(SystemMetrics.formatBytes(metrics.diskUsedBytes)) of \(SystemMetrics.formatBytes(metrics.diskTotalBytes)) disk used"
        let network = metrics.isNetworkActive
            ? "network \(SystemMetrics.formatRate(metrics.downloadBytesPerSecond)) down and \(SystemMetrics.formatRate(metrics.uploadBytesPerSecond)) up"
            : "network idle"
        return "\(cpu), \(memory), \(disk), \(network)."
    }
}

//
//  SystemMetrics.swift
//  JARVIS
//
//  Snapshot of live machine statistics rendered by the system status
//  widget. Values are produced by SystemMonitorService using Mach host
//  statistics, IOKit, getifaddrs, and FileManager volume attributes.
//

import Foundation

/// Current CPU load band, used only for color coding the readout.
enum ProcessorLoadLevel: String {
    case idle
    case moderate
    case heavy

    /// Classifies a 0 to 1 usage ratio.
    static func classify(_ usage: Double) -> ProcessorLoadLevel {
        switch usage {
        case ..<0.35: return .idle
        case 0.35..<0.7: return .moderate
        default: return .heavy
        }
    }
}

/// One sample of machine resource usage.
struct SystemMetrics: Equatable {
    /// Processor usage across all cores, 0 to 1.
    var processorUsage: Double
    /// Number of logical cores.
    var processorCount: Int
    /// Resident memory in use by all processes, in bytes.
    var memoryUsedBytes: UInt64
    /// Total physical memory in bytes.
    var memoryTotalBytes: UInt64
    /// Bytes used on the startup volume.
    var diskUsedBytes: Int64
    /// Capacity of the startup volume.
    var diskTotalBytes: Int64
    /// Bytes received per second, measured between samples.
    var downloadBytesPerSecond: Double
    /// Bytes sent per second, measured between samples.
    var uploadBytesPerSecond: Double
    /// Name of the busiest network interface at sample time.
    var networkInterfaceName: String
    /// Seconds since boot.
    var uptimeSeconds: TimeInterval
    /// When the sample was taken.
    var sampledAt: Date

    /// Not persisted. CPU load band for color coding.
    var processorLevel: ProcessorLoadLevel {
        ProcessorLoadLevel.classify(processorUsage)
    }

    /// Not persisted. Memory usage fraction, 0 to 1.
    var memoryFraction: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return Double(memoryUsedBytes) / Double(memoryTotalBytes)
    }

    /// Not persisted. Disk usage fraction, 0 to 1.
    var diskFraction: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return Double(diskUsedBytes) / Double(diskTotalBytes)
    }

    /// Not persisted. True when traffic moved between the last two samples.
    var isNetworkActive: Bool {
        downloadBytesPerSecond > 1_024 || uploadBytesPerSecond > 1_024
    }

    /// Neutral values shown until the first sample completes.
    static let placeholder = SystemMetrics(
        processorUsage: 0,
        processorCount: ProcessInfo.processInfo.processorCount,
        memoryUsedBytes: 0,
        memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
        diskUsedBytes: 0,
        diskTotalBytes: 0,
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        networkInterfaceName: "en0",
        uptimeSeconds: ProcessInfo.processInfo.systemUptime,
        sampledAt: Date()
    )

    /// Formats a byte count such as memory or disk values.
    static func formatBytes(_ bytes: Int64, style: ByteCountFormatter.CountStyle = .memory) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = style
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    /// Formats a throughput value, for example "1.2 MB/s".
    static func formatRate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        let value = max(0, bytesPerSecond)
        return formatter.string(fromByteCount: Int64(value)) + "/s"
    }

    /// Formats an uptime interval as "3d 4h 12m".
    static func formatUptime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }
}

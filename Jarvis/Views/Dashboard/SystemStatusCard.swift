//
//  SystemStatusCard.swift
//  JARVIS
//
//  Bottom left system widget: processor, memory, disk, and network,
//  sampled from the real machine by SystemMonitorService.
//

import SwiftUI

/// Live machine statistics.
struct SystemStatusCard: View {

    @Environment(AppEnvironment.self) private var environment

    /// Throughput that fills the network bar completely.
    private static let networkBarCeiling: Double = 12_500_000

    var body: some View {
        let metrics = environment.monitor.metrics

        JarvisCard(title: "System Status", symbolName: "cpu") {
            VStack(alignment: .leading, spacing: JarvisTheme.Spacing.regular) {
                MetricBar(
                    label: "Processor (\(metrics.processorCount) cores)",
                    valueText: percentText(metrics.processorUsage),
                    fraction: metrics.processorUsage,
                    tint: metrics.processorLevel.tint
                )

                MetricBar(
                    label: "Memory",
                    valueText: "\(SystemMetrics.formatBytes(Int64(metrics.memoryUsedBytes))) / \(SystemMetrics.formatBytes(Int64(metrics.memoryTotalBytes)))",
                    fraction: metrics.memoryFraction,
                    tint: JarvisTheme.Palette.accent
                )

                MetricBar(
                    label: "Disk",
                    valueText: "\(SystemMetrics.formatBytes(metrics.diskUsedBytes)) / \(SystemMetrics.formatBytes(metrics.diskTotalBytes))",
                    fraction: metrics.diskFraction,
                    tint: JarvisTheme.Palette.violet
                )

                MetricBar(
                    label: "Network (\(metrics.networkInterfaceName))",
                    valueText: "\(SystemMetrics.formatRate(metrics.downloadBytesPerSecond)) down, \(SystemMetrics.formatRate(metrics.uploadBytesPerSecond)) up",
                    fraction: min(metrics.downloadBytesPerSecond / Self.networkBarCeiling, 1),
                    tint: metrics.isNetworkActive ? JarvisTheme.Palette.success : JarvisTheme.Palette.textTertiary
                )

                HStack(spacing: JarvisTheme.Spacing.tight) {
                    Text("Uptime \(SystemMetrics.formatUptime(metrics.uptimeSeconds))")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                    Spacer(minLength: 0)
                    Text("Updated \(JarvisTimeFormat.shortTime(metrics.sampledAt))")
                        .font(JarvisTheme.Typography.caption(10))
                        .foregroundStyle(JarvisTheme.Palette.textTertiary)
                }
            }
        } accessory: {
            HStack(spacing: 6) {
                StatusDot(
                    color: environment.monitor.isMonitoring
                        ? JarvisTheme.Palette.success
                        : JarvisTheme.Palette.textTertiary,
                    size: 7
                )
                Button {
                    environment.monitor.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(JarvisTheme.Palette.textTertiary)
                .help("Sample again now")
            }
        }
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

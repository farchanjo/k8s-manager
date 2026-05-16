// Views/SelfMonitoringView.swift — app_shell bounded context
// DDD role: Presentation
// ADR ref: ADR-0027, ADR-0034

import Charts
import SwiftUI

// MARK: - SelfMonitoringView

/// Diagnostics panel showing live metrics and 60-sample sparklines.
///
/// Consumes `AsyncStream` values from `SelfMonitoringStateAggregate` and
/// renders them on `@MainActor`.  All mach-level sampling runs off-actor
/// inside `SelfMonitoringSampler`.
@MainActor
public struct SelfMonitoringView: View {

    private let aggregate: SelfMonitoringStateAggregate

    @State private var latestSample: SelfMetricSample?
    @State private var samples: [SelfMetricSample] = []

    public init(aggregate: SelfMonitoringStateAggregate) {
        self.aggregate = aggregate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                liveCounterSection
                chartsSection
            }
            .padding()
        }
        .navigationTitle("App Diagnostics")
        .task { await observeSamples() }
    }

    // MARK: Live counters

    private var liveCounterSection: some View {
        GroupBox("Live Counters") {
            if let s = latestSample {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        counterCell(label: "CPU", value: String(format: "%.1f%%", s.cpuUsagePercent))
                        counterCell(label: "RSS Memory", value: bytesFormatted(s.memoryRSSBytes))
                    }
                    GridRow {
                        counterCell(label: "Threads", value: sentinelOrInt(s.threadCount))
                        counterCell(label: "File Descriptors", value: sentinelOrInt(s.fileDescriptorCount))
                    }
                    GridRow {
                        counterCell(label: "Watch Streams", value: sentinelOrInt(s.activeWatchStreams))
                        counterCell(label: "Exec Sessions", value: sentinelOrInt(s.activeExecSessions))
                    }
                    GridRow {
                        counterCell(label: "Port Forwards", value: sentinelOrInt(s.activePortForwards))
                        counterCell(label: "Chat Streams", value: sentinelOrInt(s.activeChatStreams))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Sampled at \(s.timestampRFC3339)")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("Waiting for first sample…")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            }
        }
    }

    private func counterCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.monospacedDigit()).bold()
        }
    }

    // MARK: Charts

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            memoryChart
            cpuChart
        }
    }

    private var memoryChart: some View {
        GroupBox("Memory RSS (last \(samples.count) samples)") {
            Chart(Array(samples.suffix(60).enumerated()), id: \.offset) { idx, sample in
                LineMark(
                    x: .value("Sample", idx),
                    y: .value("MB", Double(max(0, sample.memoryRSSBytes)) / 1_048_576)
                )
                .foregroundStyle(.blue)
            }
            .chartXAxis(.hidden)
            .chartYAxisLabel("MB")
            .frame(height: 120)
        }
    }

    private var cpuChart: some View {
        GroupBox("CPU % (last \(samples.count) samples)") {
            Chart(Array(samples.suffix(60).enumerated()), id: \.offset) { idx, sample in
                LineMark(
                    x: .value("Sample", idx),
                    y: .value("%", sample.cpuUsagePercent)
                )
                .foregroundStyle(.orange)
            }
            .chartXAxis(.hidden)
            .chartYAxisLabel("%")
            .chartYScale(domain: 0...100)
            .frame(height: 120)
        }
    }

    // MARK: Async observation

    private func observeSamples() async {
        for await buffer in await aggregate.samplesStream() {
            samples = buffer
            latestSample = buffer.last
        }
    }

    // MARK: Formatting helpers

    private func bytesFormatted(_ bytes: Int) -> String {
        guard bytes != SelfMetricSample.unavailableSentinel else { return "unavailable" }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private func sentinelOrInt(_ value: Int) -> String {
        value == SelfMetricSample.unavailableSentinel ? "unavailable" : "\(value)"
    }
}

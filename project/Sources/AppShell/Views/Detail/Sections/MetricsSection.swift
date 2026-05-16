// Views/Detail/Sections/MetricsSection.swift — app_shell bounded context
// DDD role: View — Prometheus metrics chart with window + tab selector
// ADR ref: ADR-0021 (detail drawer — Onda 2), ADR-0016 (HTTP client strategy)

import SwiftUI
import Charts
import SharedKernel

// MARK: - MetricsSection

/// Displays a Swift Charts line chart for the selected metric and time window.
///
/// Falls back to a placeholder when Prometheus is unavailable.
/// The parent passes `ref` and `viewModel` so this section is pure and
/// does not own its own async task — it reacts to state in the view model.
@MainActor
public struct MetricsSection: View {

    public let clusterId: ClusterId
    public let ref: ResourceRef
    /// Observed view model that owns `metricSeries`, `selectedMetric`, etc.
    @Bindable public var viewModel: ResourceDetailViewModel

    public init(
        clusterId: ClusterId,
        ref: ResourceRef,
        viewModel: ResourceDetailViewModel
    ) {
        self.clusterId = clusterId
        self.ref = ref
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controlRow
            chartArea
        }
    }

    // MARK: Private views

    private var controlRow: some View {
        HStack {
            Label("Metrics", systemImage: "chart.xyaxis.line")
                .font(.headline)
            Spacer()
            windowPicker
            metricChips
        }
    }

    private var windowPicker: some View {
        Picker("Window", selection: $viewModel.selectedWindow) {
            ForEach(TimeWindow.allCases, id: \.self) { window in
                Text(window.rawValue).tag(window)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 72)
        .onChange(of: viewModel.selectedWindow) { _, _ in
            Task { await viewModel.refreshMetrics(clusterId: clusterId, ref: ref) }
        }
    }

    private var metricChips: some View {
        HStack(spacing: 4) {
            ForEach(MetricKind.allCases, id: \.self) { kind in
                metricChip(kind)
            }
        }
        .onChange(of: viewModel.selectedMetric) { _, _ in
            Task { await viewModel.refreshMetrics(clusterId: clusterId, ref: ref) }
        }
    }

    private func metricChip(_ kind: MetricKind) -> some View {
        let selected = viewModel.selectedMetric == kind
        return Button(kind.rawValue) {
            viewModel.selectedMetric = kind
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(selected ? Color.accentColor : Color.secondary.opacity(0.15),
                    in: Capsule())
        .foregroundStyle(selected ? .white : .primary)
    }

    @ViewBuilder
    private var chartArea: some View {
        if viewModel.prometheusUnavailable {
            prometheusPlaceholder
        } else if viewModel.metricSeries.isEmpty {
            loadingChart
        } else {
            lineChart
        }
    }

    private var lineChart: some View {
        Chart(viewModel.metricSeries) { point in
            LineMark(
                x: .value("Time", point.date),
                y: .value(viewModel.selectedMetric.rawValue, point.value)
            )
            .foregroundStyle(Color.accentColor)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: chartStrideMinutes)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { Text(yLabel(value.as(Double.self) ?? 0)) }
            }
        }
        .frame(height: 160)
        .padding(4)
    }

    private var loadingChart: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.08))
            .frame(height: 160)
            .overlay {
                ProgressView()
            }
    }

    private var prometheusPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.08))
            .frame(height: 160)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Connect Prometheus to view metrics")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
    }

    // MARK: Helpers

    private var chartStrideMinutes: Int {
        switch viewModel.selectedWindow {
        case .fiveMinutes:      return 1
        case .fifteenMinutes:   return 5
        case .oneHour:          return 15
        case .sixHours:         return 60
        case .twentyFourHours:  return 240
        }
    }

    private func yLabel(_ value: Double) -> String {
        switch viewModel.selectedMetric {
        case .cpu:     return String(format: "%.0fm", value * 1000)
        case .memory:  return byteLabel(value)
        case .network: return byteLabel(value) + "/s"
        case .io:      return byteLabel(value) + "/s"
        }
    }

    private func byteLabel(_ bytes: Double) -> String {
        let ki = 1024.0
        switch bytes {
        case ..<ki:             return String(format: "%.0fB", bytes)
        case ..<(ki * ki):      return String(format: "%.1fKi", bytes / ki)
        case ..<(ki * ki * ki): return String(format: "%.1fMi", bytes / ki / ki)
        default:                return String(format: "%.1fGi", bytes / ki / ki / ki)
        }
    }
}

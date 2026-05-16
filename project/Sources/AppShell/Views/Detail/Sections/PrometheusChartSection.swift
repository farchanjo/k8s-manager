// Views/Detail/Sections/PrometheusChartSection.swift — app_shell bounded context
// DDD role: View — Prometheus sparkline chart grid in resource detail drawer
// ADR ref: ADR-0058 (drawer chart, time-range picker, series picker, fallback states)
// ADR ref: ADR-0031 (skeleton loaders — loading state pattern)

import Charts
import MetricsObservability
import SharedKernel
import SwiftUI

// MARK: - PrometheusChartSection

/// Compact multi-series Prometheus chart for the resource detail drawer.
///
/// Renders the time-range segmented picker, series chip selector, and a
/// Swift Charts `Chart` with one `LineMark` per active series.
///
/// Delegates all query dispatch to `MetricChartViewModel`. When Prometheus
/// is not configured, unreachable, or still discovering, the chart area is
/// replaced with the appropriate fallback view per ADR-0058 §fallback.
@MainActor
public struct PrometheusChartSection: View {

    // MARK: Inputs

    public let clusterId: ClusterId
    public let ref: ResourceRef

    /// Callback invoked when the user taps "View in Metrics".
    public let onViewInMetrics: () -> Void

    @Bindable public var viewModel: MetricChartViewModel

    // MARK: Init

    public init(
        clusterId: ClusterId,
        ref: ResourceRef,
        viewModel: MetricChartViewModel,
        onViewInMetrics: @escaping () -> Void
    ) {
        self.clusterId = clusterId
        self.ref = ref
        self.viewModel = viewModel
        self.onViewInMetrics = onViewInMetrics
    }

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader
            switch viewModel.endpointStatus {
            case .notConfigured:
                notConfiguredView
            case .discovering:
                discoveringView
            case .unreachable:
                unreachableView
            case .available:
                configuredChartArea
            }
        }
    }

    // MARK: Header

    private var sectionHeader: some View {
        HStack {
            Label("Metrics", systemImage: "chart.xyaxis.line")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: Configured chart area

    @ViewBuilder
    private var configuredChartArea: some View {
        timeRangePicker
        seriesChipRow
        chartBody
        viewInMetricsButton
    }

    private var timeRangePicker: some View {
        Picker("Time range", selection: $viewModel.timeRange) {
            ForEach(MetricTimeRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: viewModel.timeRange) { _, _ in
            if case .available(let ep) = viewModel.endpointStatus {
                viewModel.refresh(ref: ref, endpoint: ep)
            }
        }
    }

    private var seriesChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(availableSeriesKeys, id: \.self) { key in
                    seriesChip(key)
                }
            }
        }
        .onChange(of: viewModel.selectedSeries) { _, _ in
            if case .available(let ep) = viewModel.endpointStatus {
                viewModel.refresh(ref: ref, endpoint: ep)
            }
        }
    }

    private func seriesChip(_ key: MetricSeriesKey) -> some View {
        let selected = viewModel.selectedSeries.contains(key)
        return Button(key.displayName) {
            if selected {
                viewModel.selectedSeries.remove(key)
            } else {
                viewModel.selectedSeries.insert(key)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            selected ? Color.accentColor : Color.secondary.opacity(0.15),
            in: Capsule()
        )
        .foregroundStyle(selected ? .white : .primary)
    }

    @ViewBuilder
    private var chartBody: some View {
        let allLoading = viewModel.selectedSeries.allSatisfy {
            if case .loading = viewModel.seriesState[$0.rawValue] { return true }
            if viewModel.seriesState[$0.rawValue] == nil { return true }
            return false
        }
        if allLoading && !viewModel.selectedSeries.isEmpty {
            loadingSkeletonView
        } else {
            lineChartView
        }
    }

    private var loadingSkeletonView: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.08))
            .frame(height: 160)
            .overlay { ProgressView() }
            .shimmering()
    }

    private var lineChartView: some View {
        Chart {
            ForEach(loadedSeriesPoints, id: \.key) { entry in
                ForEach(entry.points) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(entry.key.displayName, point.value)
                    )
                    .foregroundStyle(by: .value("Series", entry.key.displayName))
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: xStrideMinutes)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 160)
        .padding(4)
    }

    private var viewInMetricsButton: some View {
        Button(action: onViewInMetrics) {
            Label("View in Metrics", systemImage: "arrow.up.right.square")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.accentColor)
    }

    // MARK: Fallback views

    private var notConfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Configure Prometheus (Settings > Metrics) to see charts here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                // Navigation to Settings > Metrics is handled by the parent.
                onViewInMetrics()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var discoveringView: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Discovering Prometheus endpoint...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var unreachableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Prometheus unreachable")
                .font(.callout.weight(.semibold))
            Button("Retry") {
                if case .available(let ep) = viewModel.endpointStatus {
                    viewModel.refresh(ref: ref, endpoint: ep)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Computed helpers

    private var availableSeriesKeys: [MetricSeriesKey] {
        let kind = ref.kind.kind
        let cpu = DrawerChartCatalog.cpuSeries(for: kind).map(\.key)
        let mem = DrawerChartCatalog.memorySeries(for: kind).map(\.key)
        return OrderedSet(cpu + mem).elements
    }

    private var loadedSeriesPoints: [(key: MetricSeriesKey, points: [MetricPoint])] {
        viewModel.selectedSeries.compactMap { key in
            guard case .loaded(let pts) = viewModel.seriesState[key.rawValue] else { return nil }
            return (key: key, points: pts)
        }.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    private var xStrideMinutes: Int {
        switch viewModel.timeRange {
        case .fiveMinutes:      return 1
        case .fifteenMinutes:   return 5
        case .oneHour:          return 15
        case .threeHours:       return 30
        case .twentyFourHours:  return 240
        }
    }
}

// MARK: - OrderedSet (minimal, local)

/// Minimal ordered-unique collection used to deduplicate series keys while
/// preserving insertion order.
private struct OrderedSet<T: Hashable>: Sequence {
    private(set) var elements: [T] = []
    private var seen: Set<T> = []

    init(_ source: [T]) {
        for e in source {
            if seen.insert(e).inserted {
                elements.append(e)
            }
        }
    }

    func makeIterator() -> Array<T>.Iterator { elements.makeIterator() }
}

// No Array extension needed — use orderedSet.elements directly.

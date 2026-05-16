// Views/MetricsObservabilityView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI)

import SwiftUI
import Charts
import MetricsObservability

// MARK: - MetricsObservabilityView

/// Root view for the metrics and observability vertical slice.
///
/// Presents discovered Prometheus endpoints with health badges in the top
/// section. The bottom section provides a picker over the 12-entry curated
/// catalog; selecting an entry executes the query and renders the result as
/// a Swift Charts line chart (range matrix) or a plain value table (instant
/// vector / scalar).
///
/// Three-state rendering follows ADR-0031: idle and loading share a progress
/// indicator; success renders data; failure shows an inline retry affordance.
@MainActor
public struct MetricsObservabilityView: View {

    @State private var viewModel: MetricsObservabilityViewModel

    public init(viewModel: MetricsObservabilityViewModel = MetricsObservabilityViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                endpointsSection
                Divider()
                queriesSection
            }
            .navigationTitle("Metrics")
            .task { await viewModel.discoverEndpoints() }
        }
    }

    // MARK: Endpoints section

    private var endpointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Endpoints", action: {
                Task { await viewModel.discoverEndpoints() }
            })
            endpointsContent
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxHeight: 180)
    }

    @ViewBuilder
    private var endpointsContent: some View {
        switch viewModel.endpoints {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Discovering endpoints…").font(.callout).foregroundStyle(.secondary)
            }
        case .failure(let error):
            inlineError(error) { Task { await viewModel.discoverEndpoints() } }
        case .success(let list) where list.isEmpty:
            Text("No Prometheus endpoints found.")
                .font(.callout).foregroundStyle(.secondary)
        case .success(let list):
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(list, id: \.id) { endpoint in
                        endpointRow(endpoint)
                    }
                }
            }
        }
    }

    private func endpointRow(_ endpoint: PrometheusEndpoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.url).font(.headline).lineLimit(1)
                Text(endpoint.discoverySource.rawValue)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge(endpoint.status)
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: EndpointStatus) -> some View {
        Text(status.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor(status))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private func statusColor(_ status: EndpointStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .unreachable: return .red
        case .unauthorized: return .orange
        case .unknown: return .gray
        }
    }

    // MARK: Queries section

    private var queriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Curated Queries", action: {
                if let query = viewModel.selectedQuery {
                    Task { await viewModel.runCuratedQuery(query) }
                }
            })
            queryPicker
            queryResultView
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var queryPicker: some View {
        Picker("Query", selection: $viewModel.selectedQuery) {
            ForEach(CuratedQueryCatalog.all, id: \.id) { query in
                Text(query.name).tag(Optional(query))
            }
        }
        .pickerStyle(.menu)
        .onChange(of: viewModel.selectedQuery) { _, newQuery in
            guard let query = newQuery else { return }
            Task { await viewModel.runCuratedQuery(query) }
        }
    }

    @ViewBuilder
    private var queryResultView: some View {
        guard let query = viewModel.selectedQuery else {
            return AnyView(
                Text("Select a query above.")
                    .font(.callout).foregroundStyle(.secondary)
            )
        }
        return AnyView(queryResultContent(for: query))
    }

    @ViewBuilder
    private func queryResultContent(for query: CuratedQuery) -> some View {
        switch viewModel.queryResults[query.id] {
        case .none, .some(.idle):
            Text("Run a query to see results.")
                .font(.callout).foregroundStyle(.secondary)
        case .some(.loading):
            HStack {
                ProgressView()
                Text("Running query…").font(.callout).foregroundStyle(.secondary)
            }
        case .some(.failure(let error)):
            inlineError(error) {
                Task { await viewModel.runCuratedQuery(query) }
            }
        case .some(.success(let result)):
            resultRenderer(result)
        }
    }

    @ViewBuilder
    private func resultRenderer(_ result: PromQueryResult) -> some View {
        switch result {
        case .rangeMatrix(let series):
            rangeChart(series)
        case .instantVector(let samples):
            instantTable(samples)
        case .scalar(let ts, let value):
            scalarView(ts: ts, value: value)
        case .string(let text):
            Text(text).font(.body).foregroundStyle(.primary)
        }
    }

    // MARK: Result sub-views

    private func rangeChart(_ series: [TimeSeries]) -> some View {
        let capped = Array(series.prefix(5))
        return Chart {
            ForEach(Array(capped.enumerated()), id: \.offset) { idx, ts in
                ForEach(ts.points, id: \.tUnix) { point in
                    LineMark(
                        x: .value("Time", point.tUnix),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(by: .value("Series", idx))
                }
            }
        }
        .chartXAxisLabel("Unix timestamp")
        .chartYAxisLabel("Value")
        .frame(minHeight: 160)
    }

    private func instantTable(_ samples: [MetricSample]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    HStack {
                        Text(sample.metric.description)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.4f", sample.value)).font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .frame(minHeight: 80)
    }

    private func scalarView(ts: Double, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scalar").font(.caption).foregroundStyle(.secondary)
            Text(String(format: "%.6f", value))
                .font(.title2.monospacedDigit())
        }
    }

    // MARK: Shared sub-views

    private func sectionHeader(_ title: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button("Refresh", action: action).buttonStyle(.bordered).controlSize(.small)
        }
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2).foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.callout).multilineTextAlignment(.center)
            Button("Retry", action: retry).buttonStyle(.borderedProminent).controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}

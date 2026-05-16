// Views/PortForward/PortForwardDetailView.swift — app_shell bounded context
// DDD role: View — port-forward session detail panel (Onda 3)
// ADR ref: ADR-0014 (session lifecycle state machine, BytesTransferred events)

import SwiftUI
import Dependencies
import Logging
import PortForwarding
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.port_forward_detail")

// MARK: - ThroughputSample

/// Single data point in the live throughput chart (bytes/sec over a 5-minute window).
fileprivate struct ThroughputSample: Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let bytesPerSec: Double
}

// MARK: - PortForwardDetailViewModel

/// View model for the port-forward detail panel.
///
/// Subscribes to the lifecycle event stream for `sessionId` and projects
/// ``BytesTransferred`` events into a rolling 5-minute throughput chart.
@MainActor @Observable
final class PortForwardDetailViewModel {

    var session: PortForwardSession?
    fileprivate var throughput: [ThroughputSample] = []
    var errorLog: [String] = []

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var lastBytesIn: Int = 0
    @ObservationIgnored private var lastSampleTime: Date = Date()

    @ObservationIgnored
    @Dependency(\.portForwardLifecycle) private var lifecycle

    @ObservationIgnored
    @Dependency(\.portForwardRepository) private var repo

    init() {}

    func start(sessionId: UUID) async {
        do {
            let all = try await repo.loadAll()
            session = all.first { $0.id == sessionId }
        } catch {
            log.error("detail load failed — \(error)")
        }
    }

    func attachStream(_ stream: AsyncStream<PortForwardEvent>) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await event in stream {
                await self.handle(event)
            }
        }
    }

    func stop() async {
        guard let session else { return }
        await lifecycle.stop(sessionId: session.id)
        streamTask?.cancel()
        streamTask = nil
    }

    private func handle(_ event: PortForwardEvent) async {
        switch event {
        case .bytesTransferred(let e):
            let now = Date()
            let elapsed = now.timeIntervalSince(lastSampleTime)
            let rate = elapsed > 0 ? Double(e.bytesIn) / elapsed : 0
            lastSampleTime = now
            let sample = ThroughputSample(timestamp: now, bytesPerSec: rate)
            throughput.append(sample)
            // Keep last 60 samples (~5 min at 5 s interval)
            if throughput.count > 60 { throughput.removeFirst() }

        case .sessionFailed(let e):
            errorLog.append("[\(e.occurredAtRFC3339)] \(e.errorCode): \(e.detail)")

        default:
            break
        }
    }
}

// MARK: - PortForwardDetailView

/// Detail panel rendered when a `.portForward` tab is selected.
///
/// Shows session metadata, port mapping table, a simple throughput chart,
/// a scrollable error log, and a Stop button.
public struct PortForwardDetailView: View {

    public let clusterId: ClusterId
    public let forwardId: UUID

    @State private var viewModel = PortForwardDetailViewModel()

    public init(clusterId: ClusterId, forwardId: UUID) {
        self.clusterId = clusterId
        self.forwardId = forwardId
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let session = viewModel.session {
                    sessionHeader(session)
                    portMappingsTable(session)
                    throughputSection
                    if !viewModel.errorLog.isEmpty {
                        errorLogSection
                    }
                    stopButton(session)
                } else {
                    ProgressView("Loading session…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(20)
        }
        .task { await viewModel.start(sessionId: forwardId) }
    }

    // MARK: Private sections

    private func sessionHeader(_ session: PortForwardSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Session", systemImage: "arrow.left.arrow.right")
                .font(.headline)
            HStack(spacing: 16) {
                detailCell(label: "ID", value: session.id.uuidString.prefix(8).description)
                detailCell(label: "Status", value: session.status.rawValue.capitalized)
                detailCell(label: "Created", value: session.createdAtRFC3339)
            }
            HStack(spacing: 16) {
                switch session.target {
                case .pod(let t):
                    detailCell(label: "Pod", value: t.podName)
                    detailCell(label: "Namespace", value: t.namespace)
                case .service(let t):
                    detailCell(label: "Service", value: t.serviceName)
                    detailCell(label: "Namespace", value: t.namespace)
                    if let pod = t.resolvedPodName {
                        detailCell(label: "Resolved Pod", value: pod)
                    }
                }
            }
        }
    }

    private func portMappingsTable(_ session: PortForwardSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Port Mappings", systemImage: "arrow.left.arrow.right")
                .font(.subheadline)
                .fontWeight(.semibold)
            ForEach(Array(session.portMappings.enumerated()), id: \.offset) { idx, mapping in
                HStack {
                    Text("Port \(idx)")
                        .frame(width: 50, alignment: .leading)
                        .font(.caption.monospaced())
                    Text("\(mapping.bindAddress):\(mapping.localPort)")
                        .font(.body.monospaced())
                    Text("→").foregroundStyle(.secondary)
                    Text(":\(mapping.remotePort)")
                        .font(.body.monospaced())
                    if mapping.isNetworkExposed {
                        Label("Network exposed", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var throughputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Live Throughput (bytes/sec)", systemImage: "chart.xyaxis.line")
                .font(.subheadline)
                .fontWeight(.semibold)
            if viewModel.throughput.isEmpty {
                Text("No data yet — waiting for traffic…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 80)
            } else {
                ThroughputChart(samples: viewModel.throughput)
                    .frame(height: 80)
            }
        }
    }

    private var errorLogSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Error Log", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
            ScrollView(.vertical) {
                VStack(alignment: .leading) {
                    ForEach(viewModel.errorLog, id: \.self) { entry in
                        Text(entry)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }

    private func stopButton(_ session: PortForwardSession) -> some View {
        Button(role: .destructive) {
            Task { await viewModel.stop() }
        } label: {
            Label("Stop Tunnel", systemImage: "stop.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(session.status == .closed || session.status == .error)
    }

    private func detailCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
        }
    }
}

// MARK: - ThroughputChart

/// Simple line chart showing bytes/sec over the last 60 samples.
private struct ThroughputChart: View {
    let samples: [ThroughputSample]

    var body: some View {
        GeometryReader { geo in
            let maxRate = samples.map(\.bytesPerSec).max() ?? 1
            let width = geo.size.width
            let height = geo.size.height
            let stepX = samples.isEmpty ? 0 : width / Double(samples.count - 1)

            Path { path in
                for (i, sample) in samples.enumerated() {
                    let x = Double(i) * stepX
                    let y = height - (sample.bytesPerSec / maxRate) * height
                    if i == 0 { path.move(to: CGPoint(x: x, y: y))
                    } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.accentColor, lineWidth: 2)
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

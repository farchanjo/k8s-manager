// Views/PortForward/NewPortForwardSheet.swift — app_shell bounded context
// DDD role: View — port-forward creation wizard sheet (Onda 3)
// ADR ref: ADR-0014 (loopback-default binding, network-exposure warning)

import SwiftUI
import Network
import Dependencies
import Logging
import PortForwarding
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.new_port_forward_sheet")

// MARK: - TargetKind

private enum TargetKind: String, CaseIterable {
    case pod, service

    var label: String {
        switch self {
        case .pod: return "Pod"
        case .service: return "Service"
        }
    }
}

// MARK: - PortPair

private struct PortPair: Identifiable {
    let id: UUID = UUID()
    var localPort: String = ""
    var remotePort: String = ""
}

// MARK: - NewPortForwardSheet

/// Modal sheet for creating a new port-forward session.
///
/// Enforces loopback-default binding per ADR-0014 §Security. Shows a warning
/// when the operator selects `0.0.0.0` as bind address.
public struct NewPortForwardSheet: View {

    public let clusterId: ClusterId
    public let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: Form state

    @State private var targetKind: TargetKind = .pod
    @State private var targetName: String = ""
    @State private var namespace: String = "default"
    @State private var container: String = ""
    @State private var bindAddress: String = "127.0.0.1"
    @State private var portPairs: [PortPair] = [PortPair()]
    @State private var isSuggestingPort: Bool = false
    @State private var isStarting: Bool = false
    @State private var errorMessage: String?

    // MARK: Dependencies

    @Dependency(\.portForwardLifecycle) private var lifecycle

    public init(clusterId: ClusterId, onCreated: @escaping () -> Void) {
        self.clusterId = clusterId
        self.onCreated = onCreated
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    targetSection
                    portMappingsSection
                    bindAddressSection
                    if let err = errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(20)
            }
            Divider()
            sheetFooter
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private view sections

    private var sheetHeader: some View {
        HStack {
            Image(systemName: "arrow.left.arrow.right")
            Text("New Port Forward")
                .font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Target").font(.subheadline).fontWeight(.semibold)

            Picker("Kind", selection: $targetKind) {
                ForEach(TargetKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                TextField("Namespace", text: $namespace)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                TextField(targetKind == .pod ? "Pod name" : "Service name", text: $targetName)
                    .textFieldStyle(.roundedBorder)
            }

            if targetKind == .pod {
                TextField("Container (optional)", text: $container)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var portMappingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Port Mappings").font(.subheadline).fontWeight(.semibold)
                Spacer()
                Button { portPairs.append(PortPair()) } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(portPairs.count >= 16)
            }

            ForEach($portPairs) { $pair in
                PortPairRow(pair: $pair, onRemove: {
                    portPairs.removeAll { $0.id == pair.id }
                }, onSuggest: {
                    Task { await suggestPort(for: $pair) }
                })
            }
        }
    }

    private var bindAddressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bind Address").font(.subheadline).fontWeight(.semibold)
            HStack {
                TextField("127.0.0.1", text: $bindAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                if bindAddress != "127.0.0.1" {
                    Label("Exposes tunnel on local network (ADR-0014)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var sheetFooter: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
            Button("Start") { Task { await startForward() } }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isStarting)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Validation

    private var isValid: Bool {
        !targetName.isEmpty &&
        !namespace.isEmpty &&
        portPairs.allSatisfy { isPortValid($0.localPort) && isPortValid($0.remotePort) }
    }

    private func isPortValid(_ s: String) -> Bool {
        guard let n = Int(s) else { return false }
        return n >= 1 && n <= 65535
    }

    // MARK: Auto-suggest free local port

    private func suggestPort(for pair: Binding<PortPair>) async {
        isSuggestingPort = true
        defer { isSuggestingPort = false }
        let suggested = await suggestFreePort()
        if suggested > 0 {
            pair.wrappedValue.localPort = "\(suggested)"
        }
    }

    // MARK: Start

    private func startForward() async {
        guard isValid else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        let mappings = portPairs.compactMap { pair -> PortMapping? in
            guard let local = Int(pair.localPort), let remote = Int(pair.remotePort) else {
                return nil
            }
            return PortMapping(localPort: local, remotePort: remote, bindAddress: bindAddress)
        }

        let target: ForwardTarget
        switch targetKind {
        case .pod:
            target = .pod(PodTarget(namespace: namespace, podName: targetName))
        case .service:
            target = .service(ServiceTarget(namespace: namespace, serviceName: targetName))
        }

        let session = PortForwardSession(
            kubernetesContextId: UUID(),
            target: target,
            portMappings: mappings,
            createdAtRFC3339: ISO8601DateFormatter().string(from: Date())
        )

        do {
            _ = try await lifecycle.start(session: session)
            log.info("new port-forward started target=\(targetName)")
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            log.error("new port-forward failed — \(error)")
        }
    }
}

// MARK: - PortPairRow

private struct PortPairRow: View {
    @Binding var pair: PortPair
    let onRemove: () -> Void
    let onSuggest: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Local", text: $pair.localPort)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .monospacedDigit()
            Button { onSuggest() } label: {
                Image(systemName: "wand.and.stars")
            }
            .buttonStyle(.borderless)
            .help("Suggest a free local port")
            Text("→").foregroundStyle(.secondary)
            TextField("Remote", text: $pair.remotePort)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .monospacedDigit()
            Spacer()
            Button(role: .destructive) { onRemove() } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Free-port probing

/// Probes TCP ports in the `8080...8200` range and returns the first available one.
///
/// Uses `Network.NWListener` to attempt binding; a successful bind indicates the
/// port is free. Falls back to `0` (system-assigned ephemeral) when no port in
/// the range is available.
func suggestFreePort() async -> Int {
    for port in 8080...8200 {
        if await isPortAvailable(port) { return port }
    }
    return 0
}

/// Returns `true` when `port` can be bound on `127.0.0.1`.
private func isPortAvailable(_ port: Int) async -> Bool {
    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        let probe = PortAvailabilityProbe(port: port, continuation: continuation)
        probe.start()
    }
}

/// Helper that wraps `NWListener` probing in a `final class` so the
/// `CheckedContinuation` can be safely captured and called exactly once
/// without strict-concurrency `resumed` mutation warnings.
private final class PortAvailabilityProbe: @unchecked Sendable {
    private let port: Int
    private let continuation: CheckedContinuation<Bool, Never>
    private var listener: NWListener?
    private var didResume = false

    init(port: Int, continuation: CheckedContinuation<Bool, Never>) {
        self.port = port
        self.continuation = continuation
    }

    func start() {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)),
              let listener = try? NWListener(using: params, on: nwPort) else {
            continuation.resume(returning: false)
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            self?.handleState(state, listener: listener)
        }
        listener.start(queue: .global())
    }

    private func handleState(_ state: NWListener.State, listener: NWListener) {
        guard !didResume else { return }
        switch state {
        case .ready:
            didResume = true
            listener.cancel()
            continuation.resume(returning: true)
        case .failed:
            didResume = true
            listener.cancel()
            continuation.resume(returning: false)
        default:
            break
        }
    }
}

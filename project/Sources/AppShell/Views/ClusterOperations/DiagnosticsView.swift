// Views/ClusterOperations/DiagnosticsView.swift — app_shell bounded context
// DDD role: View — cluster diagnostics bundle skeleton (Onda 2)
// ADR ref: ADR-0050 (cluster operations), ADR-0027 (diagnostics export)

import SwiftUI
import UniformTypeIdentifiers
import SharedKernel

// MARK: - DiagnosticsView

/// Cluster diagnostics panel — collect and export a support bundle.
///
/// Onda 2 skeleton: triggers basic collection (kubeconfig + stub node / event
/// dumps), streams output to a log panel, and offers "Save Bundle" once done.
/// Full must-gather (live API calls, compressed archive) arrives in Onda 3+.
public struct DiagnosticsView: View {

    public let clusterId: ClusterId

    @State private var viewModel = DiagnosticsViewModel()
    @State private var isSavePresented = false

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        VStack(spacing: 0) {
            actionToolbar
            Divider()
            outputPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileExporter(
            isPresented: $isSavePresented,
            document: BundleDocument(lines: viewModel.outputLines),
            contentType: .folder,
            defaultFilename: "k8smgr-diagnostics"
        ) { _ in }
    }

    // MARK: Toolbar

    private var actionToolbar: some View {
        HStack(spacing: 12) {
            collectButton
            healthCheckButton
            connectivityButton
            Spacer()
            if case .done = viewModel.collectionState {
                saveBundleButton
            }
            if case .idle = viewModel.collectionState { } else {
                resetButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var collectButton: some View {
        Button {
            Task { await viewModel.collect(clusterId: clusterId) }
        } label: {
            Label("Collect must-gather", systemImage: "archivebox")
        }
        .buttonStyle(.bordered)
        .disabled(isCollecting)
    }

    private var healthCheckButton: some View {
        Button {
            viewModel.outputLines.append("[stub] Cluster health check — Onda 3+")
        } label: {
            Label("Health Checks", systemImage: "heart.text.clipboard")
        }
        .buttonStyle(.bordered)
        .disabled(isCollecting)
    }

    private var connectivityButton: some View {
        Button {
            viewModel.outputLines.append("[stub] API connectivity test — Onda 3+")
        } label: {
            Label("Test Connectivity", systemImage: "network.badge.shield.half.filled")
        }
        .buttonStyle(.bordered)
        .disabled(isCollecting)
    }

    private var saveBundleButton: some View {
        Button("Save Bundle") {
            isSavePresented = true
        }
        .buttonStyle(.borderedProminent)
    }

    private var resetButton: some View {
        Button("Clear", role: .destructive) {
            viewModel.reset()
        }
        .buttonStyle(.borderless)
    }

    // MARK: Output panel

    private var outputPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.outputLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    statusFooter
                        .id("bottom")
                }
                .padding(12)
            }
            .onChange(of: viewModel.outputLines.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .background(.quinary)
    }

    @ViewBuilder
    private var statusFooter: some View {
        switch viewModel.collectionState {
        case .idle:
            EmptyView()
        case .collecting(let status):
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        case .done(let url):
            Label("Bundle saved: \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let error):
            Label("Collection failed: \(error.localizedDescription)", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: Helpers

    private var isCollecting: Bool {
        if case .collecting = viewModel.collectionState { return true }
        return false
    }
}

// MARK: - BundleDocument (file exporter shim)

/// Minimal `FileDocument` used to satisfy the `fileExporter` modifier.
///
/// Captures output lines at export time from the main-actor context so no
/// actor-isolation boundary is crossed inside `fileWrapper`.
///
/// Production export will compress to `.tar.gz` via a real `DiagnosticsBundleExporter`.
private struct BundleDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.folder]

    /// Output lines captured at the moment the export sheet was presented.
    let capturedLines: [String]

    init(lines: [String]) { self.capturedLines = lines }

    init(configuration: ReadConfiguration) throws { capturedLines = [] }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let txt = capturedLines.joined(separator: "\n").data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: txt)
    }
}

// MARK: - UTType shim

private extension UTType {
    static let folder = UTType("public.folder")!
}

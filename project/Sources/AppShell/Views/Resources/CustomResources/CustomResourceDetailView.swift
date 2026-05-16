// Views/Resources/CustomResources/CustomResourceDetailView.swift — app_shell bounded context
// DDD role: View — YAML fallback for unknown CRD kinds
// ADR ref: ADR-0052 (custom resource discovery and rendering)

import SwiftUI
import ResourceBrowser
import SharedKernel

// MARK: - CustomResourceDetailView

/// Read-only YAML detail view for custom resources without a specialised renderer.
///
/// Displays collapsible sections for `metadata`, `spec`, and `status` derived
/// from the raw JSON / YAML manifest. Uses `CodeEditorPort` in read-only mode
/// when available; falls back to a styled `TextEditor` otherwise.
public struct CustomResourceDetailView: View {

    public let clusterId: ClusterId
    public let gvr: GroupVersionResource
    public let resourceName: String
    public let namespace: String?

    @State private var rawYAML: String = ""
    @State private var isMetadataExpanded: Bool = true
    @State private var isSpecExpanded: Bool = true
    @State private var isStatusExpanded: Bool = false
    @State private var isLoading: Bool = false

    /// Memberwise initialiser.
    public init(
        clusterId: ClusterId,
        gvr: GroupVersionResource,
        resourceName: String,
        namespace: String?
    ) {
        self.clusterId = clusterId
        self.gvr = gvr
        self.resourceName = resourceName
        self.namespace = namespace
    }

    public var body: some View {
        VStack(spacing: 0) {
            detailToolbar
            Divider()
            if isLoading {
                loadingView
            } else if rawYAML.isEmpty {
                emptyView
            } else {
                collapsibleSections
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private views

    private var detailToolbar: some View {
        HStack {
            Label(resourceName, systemImage: "puzzlepiece.fill")
                .font(.headline)
            if let ns = namespace {
                Text(ns)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            Text(gvr.group.isEmpty ? gvr.version : "\(gvr.group)/\(gvr.version)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var collapsibleSections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionBlock(title: "metadata", isExpanded: $isMetadataExpanded, yaml: metadataSection)
                Divider()
                sectionBlock(title: "spec", isExpanded: $isSpecExpanded, yaml: specSection)
                Divider()
                sectionBlock(title: "status", isExpanded: $isStatusExpanded, yaml: statusSection)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionBlock(
        title: String,
        isExpanded: Binding<Bool>,
        yaml: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                    Text(title)
                        .font(.callout.monospaced())
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                Text(yaml.isEmpty ? "# (empty)" : yaml)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading \(resourceName)…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No content",
            systemImage: "doc.text",
            description: Text("The resource manifest could not be loaded.")
        )
    }

    // MARK: Private — YAML section extraction

    /// Extracts the `metadata:` block from `rawYAML`.
    private var metadataSection: String { extractSection("metadata", from: rawYAML) }

    /// Extracts the `spec:` block from `rawYAML`.
    private var specSection: String { extractSection("spec", from: rawYAML) }

    /// Extracts the `status:` block from `rawYAML`.
    private var statusSection: String { extractSection("status", from: rawYAML) }

    private func extractSection(_ key: String, from yaml: String) -> String {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        var inSection = false
        var result: [String] = []

        for line in lines {
            if line.hasPrefix("\(key):") {
                inSection = true
                result.append(String(line))
                continue
            }
            guard inSection else { continue }
            if !line.isEmpty && !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                break
            }
            result.append(String(line))
        }
        return result.joined(separator: "\n")
    }
}

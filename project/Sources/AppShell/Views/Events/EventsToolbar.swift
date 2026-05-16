// Views/Events/EventsToolbar.swift — app_shell bounded context
// DDD role: View — filter/action toolbar for the events timeline (Onda 3)

import SwiftUI

// MARK: - EventsToolbar

/// Top toolbar for the events timeline tab.
///
/// Contains: type segmented control, reason dropdown, namespace dropdown,
/// age filter, search bar, pause/resume toggle, clear-filters button,
/// and an export-CSV button.
@MainActor
public struct EventsToolbar: View {

    // MARK: Bindings

    @Binding public var typeFilter: EventTypeFilter
    @Binding public var reasonFilter: String?
    @Binding public var namespaceFilter: String?
    @Binding public var ageFilter: AgeFilter
    @Binding public var searchQuery: String

    // MARK: Data

    public let availableReasons: [String]
    public let availableNamespaces: [String]
    public let isPaused: Bool

    // MARK: Actions

    public let onClear: () -> Void
    public let onPause: () -> Void
    public let onResume: () -> Void
    public let onExport: () -> Void

    // MARK: Init

    public init(
        typeFilter: Binding<EventTypeFilter>,
        reasonFilter: Binding<String?>,
        namespaceFilter: Binding<String?>,
        ageFilter: Binding<AgeFilter>,
        searchQuery: Binding<String>,
        availableReasons: [String],
        availableNamespaces: [String],
        isPaused: Bool,
        onClear: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onExport: @escaping () -> Void
    ) {
        _typeFilter = typeFilter
        _reasonFilter = reasonFilter
        _namespaceFilter = namespaceFilter
        _ageFilter = ageFilter
        _searchQuery = searchQuery
        self.availableReasons = availableReasons
        self.availableNamespaces = availableNamespaces
        self.isPaused = isPaused
        self.onClear = onClear
        self.onPause = onPause
        self.onResume = onResume
        self.onExport = onExport
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 6) {
            primaryRow
            secondaryRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Private rows

    private var primaryRow: some View {
        HStack(spacing: 8) {
            typePicker
            reasonPicker
            namespacePicker
            agePicker
            Spacer()
            pauseResumeButton
            clearButton
            exportButton
        }
    }

    private var secondaryRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            TextField("Search message or object name…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Controls

    private var typePicker: some View {
        Picker("Type", selection: $typeFilter) {
            ForEach(EventTypeFilter.allCases, id: \.self) { t in
                Text(t.rawValue).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 180)
    }

    private var reasonPicker: some View {
        Picker("Reason", selection: $reasonFilter) {
            Text("All reasons").tag(String?.none)
            Divider()
            ForEach(availableReasons, id: \.self) { r in
                Text(r).tag(String?.some(r))
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 120)
    }

    private var namespacePicker: some View {
        Picker("Namespace", selection: $namespaceFilter) {
            Text("All namespaces").tag(String?.none)
            Divider()
            ForEach(availableNamespaces, id: \.self) { ns in
                Text(ns).tag(String?.some(ns))
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 120)
    }

    private var agePicker: some View {
        Picker("Age", selection: $ageFilter) {
            ForEach(AgeFilter.allCases, id: \.self) { a in
                Text(a.rawValue).tag(a)
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 80)
    }

    private var pauseResumeButton: some View {
        Button(action: isPaused ? onResume : onPause) {
            Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(isPaused ? "Resume live updates" : "Pause live updates")
    }

    private var clearButton: some View {
        Button("Clear", action: onClear)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Clear all filters")
    }

    private var exportButton: some View {
        Button(action: onExport) {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Export visible events as CSV")
    }
}

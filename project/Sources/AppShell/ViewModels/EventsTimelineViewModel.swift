// ViewModels/EventsTimelineViewModel.swift — app_shell bounded context
// DDD role: ViewModel — cluster-wide events timeline (Onda 3)
// ADR ref: ADR-0050 (tab system), ADR-0034 (state-driven realtime UI)
// Strategy: 10s polling ring buffer (2000 events max); no watch stream
//           (high cardinality — per ADR-0050 § Events tab).

import Foundation
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel
import SwiftUI

private let log = Logger(label: "k8smgr.app_shell.events_timeline")

// MARK: - EventType

/// Kubernetes event severity.
public enum EventType: String, Sendable, CaseIterable {
    case warning = "Warning"
    case normal  = "Normal"

    /// Tint color for this severity.
    public var color: Color {
        switch self {
        case .warning: return .orange
        case .normal:  return .blue
        }
    }

    /// SF Symbol name for this severity.
    public var systemImage: String {
        switch self {
        case .warning: return "exclamationmark.triangle.fill"
        case .normal:  return "info.circle.fill"
        }
    }
}

// MARK: - EventTypeFilter

/// Segmented-control selection for event type.
public enum EventTypeFilter: String, Sendable, CaseIterable {
    case all     = "All"
    case warning = "Warning"
    case normal  = "Normal"
}

// MARK: - AgeFilter

/// Time-window selector shown in the toolbar.
public enum AgeFilter: String, Sendable, CaseIterable {
    case last5min    = "5m"
    case last15min   = "15m"
    case lastHour    = "1h"
    case last6Hours  = "6h"
    case last24Hours = "24h"
    case all         = "All"

    /// Age threshold in seconds, or `nil` for `.all`.
    public var seconds: Int? {
        switch self {
        case .last5min:    return 5 * 60
        case .last15min:   return 15 * 60
        case .lastHour:    return 60 * 60
        case .last6Hours:  return 6 * 60 * 60
        case .last24Hours: return 24 * 60 * 60
        case .all:         return nil
        }
    }
}

// MARK: - EventEntry

/// Flat projection of a Kubernetes Event for the timeline view.
public struct EventEntry: Identifiable, Sendable, Hashable {
    /// Kubernetes object UID (stable across polls).
    public let id: String
    /// Severity derived from `type` field.
    public let type: EventType
    /// Short reason code (e.g. `BackOff`, `Pulled`).
    public let reason: String
    /// Kubernetes kind of the involved object (e.g. `Pod`).
    public let objectKind: String
    /// Name of the involved object.
    public let objectName: String
    /// Namespace of the involved object, or `nil` for cluster-scoped.
    public let objectNamespace: String?
    /// Reporting component (e.g. `kubelet`).
    public let source: String
    /// ISO 8601 timestamp of first occurrence.
    public let firstSeen: String
    /// ISO 8601 timestamp of most recent occurrence.
    public let lastSeen: String
    /// Total occurrence count for recurring events.
    public let count: Int
    /// Full event message.
    public let message: String

    public init(
        id: String, type: EventType, reason: String,
        objectKind: String, objectName: String, objectNamespace: String?,
        source: String, firstSeen: String, lastSeen: String,
        count: Int, message: String
    ) {
        self.id = id
        self.type = type
        self.reason = reason
        self.objectKind = objectKind
        self.objectName = objectName
        self.objectNamespace = objectNamespace
        self.source = source
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.count = count
        self.message = message
    }
}

// MARK: - EventGroup

/// A time-bucketed group of events for the sectioned scroll view.
public struct EventGroup: Sendable {
    /// Human-readable group label (e.g. "Last 5 minutes", "Today 10:00–11:00").
    public let key: String
    /// Events within this group, sorted newest first.
    public let events: [EventEntry]

    public init(key: String, events: [EventEntry]) {
        self.key = key
        self.events = events
    }
}

// MARK: - EventsTimelineViewModel

/// View model for the full-featured events timeline tab.
///
/// Polls every 10 s for new events. Maintains a ring buffer capped at
/// `Self.ringBufferCapacity` entries (2 000). All mutation happens on
/// `@MainActor`; the polling `Task` dispatches back to main before writing.
@Observable
@MainActor
public final class EventsTimelineViewModel {

    // MARK: Constants

    private static let ringBufferCapacity = 2_000
    private static let pollInterval: Duration = .seconds(10)

    // MARK: Observable state

    /// All events currently in the ring buffer (unfiltered).
    public var events: [EventEntry] = []
    /// Selected type filter from the segmented control.
    public var typeFilter: EventTypeFilter = .all
    /// Selected reason string, or `nil` for all reasons.
    public var reasonFilter: String?
    /// Selected namespace, or `nil` for all namespaces.
    public var namespaceFilter: String?
    /// Selected age window.
    public var ageFilter: AgeFilter = .lastHour
    /// Free-text search applied to message and object name.
    public var searchQuery: String = ""
    /// Selected event id in the list (drives detail side panel).
    public var selectedEventId: EventEntry.ID?
    /// When true, new events are held until `resume()` is called.
    public var isPaused: Bool = false
    /// Timestamp of the last successful poll.
    public var lastUpdated: Date = .distantPast

    // MARK: Computed

    /// Warning event count (unfiltered total).
    public var warningCount: Int {
        events.filter { $0.type == .warning }.count
    }

    /// Normal event count (unfiltered total).
    public var normalCount: Int {
        events.filter { $0.type == .normal }.count
    }

    /// Events after applying all active filters.
    public var filteredEvents: [EventEntry] {
        events.filter { passes(entry: $0) }
    }

    /// Filtered events grouped into time buckets.
    public var groupedEvents: [EventGroup] {
        Self.group(filteredEvents)
    }

    /// Distinct reasons seen in the current ring buffer.
    public var availableReasons: [String] {
        Array(Set(events.map(\.reason))).sorted()
    }

    /// Distinct namespaces seen in the current ring buffer.
    public var availableNamespaces: [String] {
        Array(Set(events.compactMap(\.objectNamespace))).sorted()
    }

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    // MARK: Private state

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var pendingBuffer: [EventEntry] = []
    @ObservationIgnored private var currentClusterId: ClusterId?
    @ObservationIgnored private var currentScope: EventScope?

    // MARK: Init / deinit

    public init() {}

    nonisolated deinit { streamTask?.cancel() }

    // MARK: - Lifecycle

    /// Begins the 10-second poll loop for the given cluster and optional scope.
    public func start(clusterId: ClusterId, scope: EventScope?) async {
        currentClusterId = clusterId
        currentScope = scope
        streamTask?.cancel()
        await poll(clusterId: clusterId, scope: scope)
        schedulePolling(clusterId: clusterId, scope: scope)
    }

    /// Pauses accumulation; new arrivals are queued in `pendingBuffer`.
    public func pause() {
        isPaused = true
    }

    /// Flushes `pendingBuffer` and resumes live updates.
    public func resume() async {
        isPaused = false
        if !pendingBuffer.isEmpty {
            merge(pendingBuffer)
            pendingBuffer.removeAll()
        }
        guard let id = currentClusterId, let scope = currentScope else { return }
        await poll(clusterId: id, scope: scope)
    }

    /// Resets all filters to their defaults.
    public func clearFilters() {
        typeFilter = .all
        reasonFilter = nil
        namespaceFilter = nil
        ageFilter = .lastHour
        searchQuery = ""
    }

    /// Exports the current filtered events as a CSV file URL.
    ///
    /// - Returns: A `file://` URL for the exported CSV, or `nil` on failure.
    public func exportEvents() async -> URL? {
        let snapshot = filteredEvents
        return await Task.detached(priority: .utility) {
            Self.writeCSV(snapshot)
        }.value
    }

    // MARK: - Private polling

    private func schedulePolling(clusterId: ClusterId, scope: EventScope?) {
        streamTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: EventsTimelineViewModel.pollInterval)
                guard !Task.isCancelled else { break }
                await self?.poll(clusterId: clusterId, scope: scope)
            }
        }
    }

    private func poll(clusterId: ClusterId, scope: EventScope?) async {
        let ns = namespace(for: scope)
        log.debug("events poll cluster=\(clusterId.rawValue) ns=\(ns ?? "<all>")")
        let gvk = GroupVersionKind.core("Event")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: ns, clusterId: clusterId)
            let incoming = items.map { Self.project(item: $0, scope: scope) }
            lastUpdated = .now
            if isPaused {
                pendingBuffer = incoming
            } else {
                merge(incoming)
            }
        } catch {
            log.error("events poll error — \(error)")
        }
    }

    // MARK: - Ring buffer merge

    private func merge(_ incoming: [EventEntry]) {
        var dict = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        for entry in incoming { dict[entry.id] = entry }
        var merged = Array(dict.values)
            .sorted { $0.lastSeen > $1.lastSeen }
        if merged.count > Self.ringBufferCapacity {
            merged = Array(merged.prefix(Self.ringBufferCapacity))
        }
        events = merged
    }

    // MARK: - Filter predicate

    private func passes(entry: EventEntry) -> Bool {
        if typeFilter != .all && entry.type.rawValue != typeFilter.rawValue { return false }
        if let r = reasonFilter, entry.reason != r { return false }
        if let ns = namespaceFilter, entry.objectNamespace != ns { return false }
        if let seconds = ageFilter.seconds {
            guard let date = ISO8601DateFormatter().date(from: entry.lastSeen) else { return true }
            if Date().timeIntervalSince(date) > Double(seconds) { return false }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            let inMessage = entry.message.lowercased().contains(q)
            let inName = entry.objectName.lowercased().contains(q)
            if !inMessage && !inName { return false }
        }
        return true
    }

    // MARK: - Grouping

    private static func group(_ entries: [EventEntry]) -> [EventGroup] {
        let formatter = ISO8601DateFormatter()
        let now = Date()
        var buckets: [(key: String, threshold: TimeInterval)] = [
            ("Last 5 minutes",   5 * 60),
            ("Last 15 minutes",  15 * 60),
            ("Last hour",        60 * 60),
            ("Last 6 hours",     6 * 60 * 60),
            ("Last 24 hours",    24 * 60 * 60),
        ]
        var result: [EventGroup] = []
        var remaining = entries
        for bucket in buckets {
            let matching = remaining.filter { entry in
                guard let date = formatter.date(from: entry.lastSeen) else { return false }
                return now.timeIntervalSince(date) <= bucket.threshold
            }
            let others = remaining.filter { entry in
                guard let date = formatter.date(from: entry.lastSeen) else { return true }
                return now.timeIntervalSince(date) > bucket.threshold
            }
            if !matching.isEmpty {
                result.append(EventGroup(key: bucket.key, events: matching))
            }
            remaining = others
        }
        if !remaining.isEmpty {
            result.append(EventGroup(key: "Older", events: remaining))
        }
        return result
    }

    // MARK: - Projection

    private static func project(
        item: ResourceListItem,
        scope: EventScope?
    ) -> EventEntry {
        let rawType = item.annotations["type"] ?? "Normal"
        let eventType: EventType = rawType == "Warning" ? .warning : .normal
        return EventEntry(
            id: item.uid,
            type: eventType,
            reason: item.annotations["reason"] ?? "—",
            objectKind: item.annotations["involvedObject.kind"] ?? "—",
            objectName: item.annotations["involvedObject.name"] ?? item.name,
            objectNamespace: item.namespace,
            source: item.annotations["source.component"] ?? "—",
            firstSeen: item.annotations["firstTimestamp"] ?? item.creationTimestamp,
            lastSeen: item.annotations["lastTimestamp"] ?? item.creationTimestamp,
            count: Int(item.annotations["count"] ?? "1") ?? 1,
            message: item.annotations["message"] ?? "—"
        )
    }

    // MARK: - Namespace resolution

    private func namespace(for scope: EventScope?) -> String? {
        guard let scope else { return nil }
        switch scope {
        case .clusterWide:         return nil
        case .namespace(let ns):   return ns
        case .resource(let ref):   return ref.namespace
        }
    }

    // MARK: - CSV export

    private nonisolated static func writeCSV(_ entries: [EventEntry]) -> URL? {
        let header = "id,type,reason,objectKind,objectName,namespace,source,firstSeen,lastSeen,count,message"
        let rows = entries.map { e in
            let msg = e.message.replacingOccurrences(of: "\"", with: "\"\"")
            return "\(e.id),\(e.type.rawValue),\(e.reason),\(e.objectKind),\(e.objectName),"
                + "\(e.objectNamespace ?? ""),\(e.source),\(e.firstSeen),\(e.lastSeen),"
                + "\(e.count),\"\(msg)\""
        }
        let csv = ([header] + rows).joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            log.error("csv export failed — \(error)")
            return nil
        }
    }
}

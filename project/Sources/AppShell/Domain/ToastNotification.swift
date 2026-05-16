// Domain/ToastNotification.swift — app_shell bounded context
// DDD role: AggregateRoot (#ToastStack), ValueObject (#Toast, #ToastDomainAction), ReadModel (#ToastHistoryEntry)
// CUE source: docs/arch/contexts/app_shell/schemas/toast_notification.cue
// ADR ref: ADR-0032

import Foundation

// MARK: - ToastDomainSeverity

/// Domain-layer severity for the `Toast` value object (Codable, no SwiftUI dependency).
///
/// Note: the view layer uses the existing `ToastSeverity` in `ToastStackView.swift`.
/// This type is the persistence-safe counterpart consumed by aggregates and ports.
public enum ToastDomainSeverity: String, Sendable, Codable {
    case success, info, warning, error, neutral

    /// Auto-dismiss delay in milliseconds per ADR-0032.
    public var autoDismissMs: Int {
        switch self {
        case .success, .info: return 3_000
        case .neutral: return 4_000
        case .warning: return 5_000
        case .error: return 8_000
        }
    }

    /// Default SF Symbol name when `Toast.iconSymbolName` is absent.
    public var defaultIconSymbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .neutral: return "bell.fill"
        }
    }
}

// MARK: - ToastDomainAction

/// Domain-layer CTA action (Codable, no closure references).
public struct ToastDomainAction: Sendable, Codable {
    /// Button label (1–24 chars).
    public let label: String
    /// Kebab-case handler identifier (e.g. `"mutation.undo"`, `"cluster.retry"`).
    public let actionId: String
    /// Key-value context for the handler. No credential material allowed.
    public let payload: [String: String]

    public init(label: String, actionId: String, payload: [String: String] = [:]) {
        self.label = label
        self.actionId = actionId
        self.payload = payload
    }
}

// MARK: - Toast (ValueObject)

/// Immutable domain notification card. Assigned a UUIDv7 by `ToastDomainEmitter`.
///
/// This is the domain-layer `Toast` (Codable). The view layer uses `ToastNotification` in
/// `ToastStackView.swift` which carries a SwiftUI-bound action closure.
public struct Toast: Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let message: String?
    public let severity: ToastDomainSeverity
    public let iconSymbolName: String?
    public let emittedAtRFC3339: String
    public let autoDismissMs: Int
    public var pinned: Bool
    public let action: ToastDomainAction?

    public init(
        id: String,
        title: String,
        message: String? = nil,
        severity: ToastDomainSeverity,
        iconSymbolName: String? = nil,
        emittedAtRFC3339: String,
        pinned: Bool = false,
        action: ToastDomainAction? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.iconSymbolName = iconSymbolName
        self.emittedAtRFC3339 = emittedAtRFC3339
        self.autoDismissMs = severity.autoDismissMs
        self.pinned = pinned
        self.action = action
    }
}

// MARK: - DomainToastStack (AggregateRoot)

/// Domain-layer aggregate owning the lifecycle of all active toasts.
///
/// Persisted under `app_shell/toast_stack` in `local_persistence`.
/// Renamed to `DomainToastStack` to avoid collision with the view-layer `ToastStackViewModel`.
public struct DomainToastStack: Sendable, Codable, Identifiable {

    public enum Position: String, Sendable, Codable {
        case bottomRight = "bottom_right"
        case bottomLeft = "bottom_left"
        case topRight = "top_right"
        case topLeft = "top_left"
    }

    public let id: String
    public var position: Position
    /// Maximum concurrent toasts [1, 10]. Default 5.
    public var maxConcurrent: Int
    /// Currently visible toasts, newest-first. Invariant: count ≤ maxConcurrent.
    public var activeToasts: [Toast]
    /// Toasts waiting because the stack is at capacity and all are pinned.
    public var queue: [Toast]

    public init(
        id: String,
        position: Position = .bottomRight,
        maxConcurrent: Int = 5,
        activeToasts: [Toast] = [],
        queue: [Toast] = []
    ) {
        self.id = id
        self.position = position
        self.maxConcurrent = maxConcurrent
        self.activeToasts = activeToasts
        self.queue = queue
    }

    /// Enqueues a toast; evicts the oldest non-pinned toast when the stack is full.
    public mutating func enqueue(_ toast: Toast) {
        if activeToasts.count < maxConcurrent {
            activeToasts.insert(toast, at: 0)
            return
        }
        if let idx = activeToasts.indices.reversed().first(where: { !activeToasts[$0].pinned }) {
            activeToasts.remove(at: idx)
            activeToasts.insert(toast, at: 0)
        } else {
            queue.append(toast)
        }
    }

    /// Dismisses a toast by id; promotes the next queued toast if one exists.
    public mutating func dismiss(id: String) {
        activeToasts.removeAll { $0.id == id }
        if !queue.isEmpty, activeToasts.count < maxConcurrent {
            activeToasts.insert(queue.removeFirst(), at: 0)
        }
    }
}

// MARK: - ToastHistoryEntry (ReadModel)

/// Persisted to the `toast_history` SQLite table. Retains last 100 entries.
public struct ToastHistoryEntry: Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let message: String?
    public let severity: ToastDomainSeverity
    public let iconSymbolName: String?
    public let emittedAtRFC3339: String
    public let actionId: String?
    public let actionPayloadJson: String?
    public let pinned: Bool
    public let dismissedAtRFC3339: String?

    public init(from toast: Toast, dismissedAtRFC3339: String? = nil) {
        self.id = toast.id
        self.title = toast.title
        self.message = toast.message
        self.severity = toast.severity
        self.iconSymbolName = toast.iconSymbolName
        self.emittedAtRFC3339 = toast.emittedAtRFC3339
        self.actionId = toast.action?.actionId
        self.actionPayloadJson = nil
        self.pinned = toast.pinned
        self.dismissedAtRFC3339 = dismissedAtRFC3339
    }
}

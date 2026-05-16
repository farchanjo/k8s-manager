// Ports/ToastEmitterPort.swift — app_shell bounded context
// DDD role: Port
// ADR ref: ADR-0032

import Foundation

// MARK: - ToastEmitterPort

/// Port for emitting domain toast notifications from any bounded context.
///
/// The production `ToastDomainEmitter` assigns UUIDv7, computes `autoDismissMs` from severity,
/// enqueues to `ToastStackAggregate`, and writes to the `toast_history` SQLite table.
public protocol ToastEmitterPort: Sendable {
    /// Emits a domain toast notification.
    func emit(
        title: String,
        message: String?,
        severity: ToastDomainSeverity,
        iconSymbolName: String?,
        pinned: Bool,
        action: ToastDomainAction?
    ) async
}

// MARK: - ToastDomainEmitter (production)

/// Production `ToastEmitterPort` backed by `ToastStackAggregate`.
public struct ToastDomainEmitter: ToastEmitterPort, Sendable {
    private let aggregate: ToastStackAggregate

    public init(aggregate: ToastStackAggregate) {
        self.aggregate = aggregate
    }

    public func emit(
        title: String,
        message: String? = nil,
        severity: ToastDomainSeverity,
        iconSymbolName: String? = nil,
        pinned: Bool = false,
        action: ToastDomainAction? = nil
    ) async {
        let toast = Toast(
            id: UUID().uuidString,
            title: title,
            message: message,
            severity: severity,
            iconSymbolName: iconSymbolName,
            emittedAtRFC3339: ISO8601DateFormatter().string(from: Date()),
            pinned: pinned,
            action: action
        )
        await aggregate.enqueue(toast)
    }
}

// MARK: - RecordingToastEmitter (test double)

/// Test double that records emitted toasts for assertion in unit tests.
public actor RecordingToastEmitter: ToastEmitterPort {
    public private(set) var emitted: [Toast] = []

    public init() {}

    public func emit(
        title: String,
        message: String? = nil,
        severity: ToastDomainSeverity,
        iconSymbolName: String? = nil,
        pinned: Bool = false,
        action: ToastDomainAction? = nil
    ) async {
        let toast = Toast(
            id: UUID().uuidString,
            title: title,
            message: message,
            severity: severity,
            iconSymbolName: iconSymbolName,
            emittedAtRFC3339: ISO8601DateFormatter().string(from: Date()),
            pinned: pinned,
            action: action
        )
        emitted.append(toast)
    }
}

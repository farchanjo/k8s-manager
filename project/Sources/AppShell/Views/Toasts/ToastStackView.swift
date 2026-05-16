// Views/Toasts/ToastStackView.swift — app_shell bounded context
// DDD role: View + ViewModel for the #ToastStack AggregateRoot
//           View-layer severity palette, action closure wrapper, toast card model
// ADR ref: ADR-0032 (toast notification system)
//          ADR-0034 (state-driven realtime UI — @Observable, no Combine)
//
// Type naming contract (prevents ambiguity with Domain/ToastNotification.swift):
//   ToastSeverity  — severity enum: view layer owns this (domain files reference it here).
//   ToastAction    — closure-based CTA wrapper: view layer (domain uses ToastDomainAction for Codable).
//   ToastCard      — view-layer notification card (domain uses Toast for the Codable value object).
//   ToastStackViewModel — @Observable orchestrator for the SwiftUI overlay.
//   ToastViewEmitter    — @MainActor convenience emitter for views (wraps ToastEmitterPort).

import SwiftUI

// MARK: - ToastSeverity

/// Severity levels matching the ADR-0032 severity palette.
///
/// This is the canonical definition referenced by `Toast` (domain) and `ToastEmitterPort`.
public enum ToastSeverity: String, Sendable, CaseIterable, Codable {
    case success, info, warning, error, neutral

    /// Auto-dismiss delay in milliseconds per ADR-0032 § Severity palette.
    public var autoDismissMs: Int {
        switch self {
        case .success: return 3_000
        case .info:    return 3_000
        case .warning: return 5_000
        case .error:   return 8_000
        case .neutral: return 4_000
        }
    }

    public var iconSymbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        case .neutral: return "bell.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .success: return .green
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        case .neutral: return .gray
        }
    }

    /// VoiceOver-friendly severity label.
    public var accessibilityDescription: String { rawValue }
}

// MARK: - ToastAction

/// View-layer CTA — wraps a closure for in-process handling.
///
/// The domain layer uses `ToastDomainAction` (Codable, actionId-based) for persistence.
/// This wrapper is the runtime counterpart resolved at view composition time.
public struct ToastAction: Sendable {
    /// Button label (≤ 24 characters per ADR-0032).
    public let label: String
    /// Handler invoked on tap — runs on `@MainActor`.
    public let handler: @MainActor @Sendable () -> Void

    public init(label: String, handler: @escaping @MainActor @Sendable () -> Void) {
        self.label = label
        self.handler = handler
    }
}

// MARK: - ToastCard

/// View-layer notification card model.
///
/// Distinct from the domain's `Toast` (Codable value object) to avoid type ambiguity.
/// `ToastStackViewModel` manages a `[ToastCard]` array; `ToastEmitterPort` produces
/// domain `Toast` objects which are mapped to `ToastCard` on enqueue.
public struct ToastCard: Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let message: String?
    public let severity: ToastSeverity
    public let iconSymbolName: String?
    public let emittedAt: Date
    /// When `true`, the card never auto-dismisses and survives FIFO eviction.
    public let pinned: Bool
    public let action: ToastAction?

    public init(
        id: UUID = UUID(),
        title: String,
        message: String? = nil,
        severity: ToastSeverity,
        iconSymbolName: String? = nil,
        emittedAt: Date = .now,
        pinned: Bool = false,
        action: ToastAction? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.iconSymbolName = iconSymbolName
        self.emittedAt = emittedAt
        self.pinned = pinned
        self.action = action
    }
}

// MARK: - ToastStackViewModel

/// `@Observable` + `@MainActor` view model owning the active toast queue.
///
/// Enforces ADR-0032 invariants:
/// - `maxConcurrent == 5` (FIFO drop of oldest non-pinned on overflow).
/// - Auto-dismiss timers via structured concurrency `Task`s.
/// - Hover pause / resume of all active timers.
@Observable
@MainActor
public final class ToastStackViewModel {

    // MARK: Public state

    /// Active toast cards rendered by `ToastStackView`. Newest at the end.
    public private(set) var activeToasts: [ToastCard] = []

    // MARK: Private

    /// Overflow queue: holds incoming toasts when all 5 slots are pinned.
    private var overflowQueue: [ToastCard] = []
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    public static let maxConcurrent = 5

    public init() {}

    // MARK: Enqueue

    /// Enqueues a new toast card. Applies FIFO-drop policy if the stack is at capacity.
    public func enqueue(_ toast: ToastCard) {
        postAccessibilityAnnouncement(toast)

        if activeToasts.count < Self.maxConcurrent {
            activeToasts.append(toast)
            scheduleAutoDismiss(for: toast)
        } else {
            // ADR-0032 § Stack capacity: evict oldest non-pinned, or overflow queue.
            if let evictIndex = activeToasts.firstIndex(where: { !$0.pinned }) {
                let evicted = activeToasts.remove(at: evictIndex)
                cancelDismissTask(for: evicted.id)
                activeToasts.append(toast)
                scheduleAutoDismiss(for: toast)
            } else {
                // All current toasts are pinned — queue incoming.
                overflowQueue.append(toast)
            }
        }
    }

    // MARK: Dismiss

    /// Removes a toast by id and schedules the next overflow item if any.
    public func dismiss(id: UUID) {
        cancelDismissTask(for: id)
        activeToasts.removeAll { $0.id == id }
        drainOverflow()
    }

    // MARK: Hover pause / resume (ADR-0032 § auto-dismiss timers)

    /// Cancels all active dismiss timers while the pointer is over the stack.
    public func pauseAllTimers() {
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
    }

    /// Re-schedules dismiss timers with remaining duration calculated from `emittedAt`.
    public func resumeAllTimers() {
        for toast in activeToasts where !toast.pinned {
            scheduleAutoDismiss(for: toast)
        }
    }

    // MARK: Private helpers

    private func scheduleAutoDismiss(for toast: ToastCard) {
        guard !toast.pinned else { return }
        let toastId = toast.id
        let elapsed = Date.now.timeIntervalSince(toast.emittedAt) * 1_000
        let remaining = Double(toast.severity.autoDismissMs) - elapsed
        guard remaining > 0 else { dismiss(id: toastId); return }

        dismissTasks[toastId] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(remaining)))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismiss(id: toastId) }
        }
    }

    private func cancelDismissTask(for id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)
    }

    private func drainOverflow() {
        guard !overflowQueue.isEmpty,
              activeToasts.count < Self.maxConcurrent else { return }
        let next = overflowQueue.removeFirst()
        activeToasts.append(next)
        scheduleAutoDismiss(for: next)
    }

    private func postAccessibilityAnnouncement(_ toast: ToastCard) {
        let message = "\(toast.severity.accessibilityDescription): \(toast.title)"
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: message]
        )
    }
}

// MARK: - ToastViewEmitter

/// `@MainActor`-bound convenience emitter for views that need to push toasts
/// without going through the full `ToastEmitterPort` actor chain.
///
/// Use `ToastEmitter` (production) for cross-actor domain calls.
/// Use `ToastViewEmitter` inside `@MainActor` contexts for immediate view-layer toasts.
@MainActor
public final class ToastViewEmitter {

    private let stack: ToastStackViewModel

    public init(stack: ToastStackViewModel) {
        self.stack = stack
    }

    public func emit(
        title: String,
        severity: ToastSeverity,
        message: String? = nil,
        iconSymbolName: String? = nil,
        action: ToastAction? = nil,
        pinned: Bool = false
    ) {
        let card = ToastCard(
            title: title,
            message: message,
            severity: severity,
            iconSymbolName: iconSymbolName,
            pinned: pinned,
            action: action
        )
        stack.enqueue(card)
    }
}

// MARK: - ToastCardView

/// Single toast card matching ADR-0032 anatomy:
/// severity icon • title • optional message • optional action button • dismiss button.
@MainActor
struct ToastCardView: View {
    let toast: ToastCard
    let onDismiss: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            severityIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let msg = toast.message {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let action = toast.action {
                    Button(action.label) {
                        action.handler()
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(toast.severity.tintColor)
                    .accessibilityLabel(action.label)
                }
            }
            Spacer(minLength: 0)
            dismissButton
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(toast.severity.tintColor.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var severityIcon: some View {
        Image(systemName: toast.iconSymbolName ?? toast.severity.iconSymbol)
            .font(.system(size: 20))
            .foregroundStyle(toast.severity.tintColor)
            .accessibilityHidden(true)
    }

    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss notification")
    }

    private var accessibilityDescription: String {
        var parts = [toast.severity.accessibilityDescription, toast.title]
        if let msg = toast.message { parts.append(msg) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - ToastStackView

/// Top-trailing overlay of `ToastCard` cards.
///
/// Placed via `.overlay(alignment: .topTrailing)` on the root window content
/// through `KeyboardShortcutsHandler`.
/// Auto-dismisses per severity; FIFO-drops oldest non-pinned on overflow (max 5).
/// Hover pauses all auto-dismiss timers while the pointer is over the stack.
@MainActor
public struct ToastStackView: View {

    @State var viewModel: ToastStackViewModel

    public init(viewModel: ToastStackViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(viewModel.activeToasts) { toast in
                ToastCardView(toast: toast) {
                    withAnimation {
                        viewModel.dismiss(id: toast.id)
                    }
                }
                .transition(
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                          )
                )
            }
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
        .animation(.easeInOut(duration: 0.22), value: viewModel.activeToasts.map(\.id))
        .onHover { hovering in
            if hovering {
                viewModel.pauseAllTimers()
            } else {
                viewModel.resumeAllTimers()
            }
        }
    }
}

// MARK: - AppKit import for NSAccessibility

import AppKit

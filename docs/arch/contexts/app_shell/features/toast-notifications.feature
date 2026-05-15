# DDD role: BehaviouralSpecification
@adr-0032
Feature: Toast notification system
  As an operator of K8sManager
  I want non-intrusive, actionable notifications for all operations
  So that I receive immediate feedback without losing focus on my current task

  Background:
    Given the application is running on macOS 14 or later
    And the toast stack is anchored to the bottom-right corner of the main window
    And the operator has at least one cluster context configured

  Scenario: Apply success emits a green success toast
    Given the operator applies a valid Deployment manifest to a cluster
    When the Kubernetes API confirms the apply with status 200
    Then a success toast appears in the bottom-right corner
    And the toast title is "Deployment applied successfully"
    And the toast background uses the "statusHealthy" color token
    And the toast icon is "checkmark.circle.fill"
    And an "Undo" action button is visible on the toast
    And the toast auto-dismisses after 3 000 ms

  Scenario: Apply failure emits a red error toast with Retry action
    Given the operator applies a Deployment manifest with an invalid image tag
    When the Kubernetes API returns a 422 Unprocessable Entity error
    Then an error toast appears in the bottom-right corner
    And the toast title is "Apply failed"
    And the toast background uses the "statusError" color token
    And a "Retry" action button is visible on the toast
    And the toast auto-dismisses after 8 000 ms

  Scenario: Delete pod emits success toast with Undo action within 5-second window
    Given the operator deletes a running Pod named "frontend-abc123"
    When the Kubernetes API confirms the deletion
    Then a success toast appears with title "Pod deleted"
    And an "Undo" action button is visible on the toast
    When the operator presses "Undo" within 5 seconds of the deletion
    Then the MutationUndoService is called with the deletion command ID
    And the pod is re-created on the cluster
    And a new info toast confirms "Undo applied"

  Scenario: Kubeconfig reload emits info toast
    Given the operator's kubeconfig file has changed on disk
    When K8sManager detects the change and reloads the kubeconfig
    Then an info toast appears with title "Kubeconfig reloaded"
    And no action button is shown
    And the toast auto-dismisses after 3 000 ms

  Scenario: Maximum 5 toasts shown simultaneously with FIFO drop
    Given 5 toasts are currently visible in the toast stack
    And none of the 5 toasts are pinned
    When a sixth toast is emitted
    Then the oldest non-pinned toast is immediately dismissed
    And the sixth toast appears in its place
    And the stack always shows exactly 5 toasts

  Scenario: Pinned toast prevents auto-dismiss
    Given a warning toast about a degraded node is emitted
    When the operator clicks the pin icon on the warning toast
    Then the toast's "pinned" property is set to true
    And the toast does not auto-dismiss after 5 000 ms
    And the toast remains visible until the operator explicitly dismisses it
    When the operator clicks the dismiss button on the pinned toast
    Then the toast is removed from the stack

  Scenario: VoiceOver announces each toast on emission
    Given VoiceOver is enabled
    When an error toast is emitted with title "Cluster connection failed"
    Then UIAccessibility.post is called with notification type ".announcement"
    And the announcement text is "error: Cluster connection failed"

  Scenario: Toast history is visible in Settings Activity Log
    Given the operator has performed several operations that emitted toasts
    When the operator navigates to Settings → Activity Log
    Then the last 100 toast entries are listed in reverse chronological order
    And each entry shows title, severity, timestamp, and action label if present
    And the operator can filter entries by severity
    And entries older than the 100-entry limit are not shown

  Scenario: Reduce Motion replaces slide animation with fade
    Given the system accessibility setting "Reduce Motion" is enabled
    When a toast is emitted
    Then the toast entrance animation uses opacity fade only
    And no slide or scale transform is applied
    When the toast is dismissed
    Then the exit animation also uses opacity fade only

  # ---------------------------------------------------------------------------
  # F19 — Notification delivery dropped (ADR-0041)
  # Detecting entity: DomainEventBusActor (shared kernel infrastructure)
  # Detection: AsyncStream.Continuation.yield(with:) returns .dropped;
  #            DomainEventBusActor emits DomainEventDropped to the meta-stream.
  # Recovery: subscriber triggers read-model reconciliation from local_persistence.
  # ---------------------------------------------------------------------------

  @F19 @chaos
  Scenario: OS notification permission revoked mid-session — queued toasts logged in diagnostics
    Given the operator granted macOS notification permission at app launch
    And K8sManager has a pending toast queue with 3 undelivered toasts
    When the operator revokes K8sManager's notification permission in System Settings while the app is running
    Then the NSUserNotificationCenter delegate receives a permission-denied callback
    And the toast notification pipeline emits a DomainEventDropped meta-event for each undelivered toast
    And each undelivered toast is written to the diagnostics log at level WARN with its title and timestamp
    And those toast entries appear in the self-monitoring diagnostics panel under "Dropped notifications"
    And no unhandled error or crash occurs in the toast stack

  @F19 @chaos
  Scenario: System tray suspended — queued toasts replayed on resume within TTL
    Given the macOS system tray is suspended (e.g. via a fast-user-switch or display sleep)
    And 2 toasts are emitted while the tray is suspended
    When the tray suspension lifts and the application becomes active again (NSApplicationDidBecomeActive)
    Then the toast pipeline replays each queued toast in emission order
    And each toast is delivered only if its 5-minute TTL has not expired
    And any toast whose TTL expired during suspension is discarded without display
    And a DomainEventDropped meta-event is emitted for each TTL-expired toast
    And the diagnostics log records the drop with subscriberId, drop count, and expiry timestamp

  @F19 @chaos
  Scenario: Toast notification pipeline crash — error logged with no user-facing cascade
    Given the DomainEventBusActor has at least one toast-notification subscriber registered
    When the subscriber's AsyncStream buffer overflows (more than 64 events enqueued per ADR-0040)
    Then the DomainEventBusActor observes a .dropped result from AsyncStream.Continuation.yield(with:)
    And a DomainEventDropped envelope is emitted to the meta-stream with the subscriber ID and drop count
    And an "events.dropped" entry is written to the diagnostics log (not the mutation audit log)
    And the toast stack continues operating normally — no blocking dialog or error banner is shown
    And on the next read-model reconciliation the subscriber re-queries local_persistence for current state

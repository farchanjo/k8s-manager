@adr-0034
Feature: State-driven realtime UI architecture
  As an operator of K8sManager
  I want the UI to reflect live cluster state without manual refresh
  So that I can trust what I see and act on accurate information at all times

  Background:
    Given the application is running on macOS 14 or later
    And the operator has an active connection to a Kubernetes cluster
    And the application is using the Observation framework with @Observable view models

  Scenario: Pod status change in cluster reflects in UI within 500 ms without polling
    Given the operator is viewing the pod list for namespace "default"
    And the pod "backend-deploy-xyz" has status "Running"
    When the pod's status changes to "CrashLoopBackOff" on the cluster
    Then the pod list in the UI shows status "CrashLoopBackOff" for "backend-deploy-xyz"
    Within 500 ms of the change being committed to the Kubernetes API
    And no manual refresh was triggered by the operator
    And no Timer-based polling was invoked in the application

  Scenario: Sidebar updates automatically when a watch event arrives
    Given the operator is viewing the cluster sidebar
    And a new namespace "staging" is created on the cluster
    When the Kubernetes API emits a namespace watch event for "staging"
    Then the namespace "staging" appears in the sidebar namespace list
    And the update is applied without any operator-initiated action
    And the sidebar view is re-rendered via @Observable state change tracking

  Scenario: No manual refresh button is visible in the primary resource list
    Given the operator is viewing the pod list for namespace "production"
    Then no "Refresh" button is visible in the content list toolbar
    And no "Refresh" keyboard shortcut is registered for the content list view
    And the pod list stays current via the Kubernetes watch stream

  Scenario: Reduce Motion setting is respected for state transition animations
    Given the system accessibility setting "Reduce Motion" is enabled
    When an @Observable state change causes the pod list to re-render
    Then no spring animation or opacity crossfade is applied to the row update
    And the change is applied immediately without a transition duration
    And the operator can still read the updated status clearly

  Scenario: Cancellation of watch stream cleans up AsyncStream gracefully
    Given the pod list view model has an active watch stream from ClusterSessionActor
    When the operator navigates away from the pod list view
    Then the view model's watchTask is cancelled via Task.cancel()
    And the AsyncThrowingStream onTermination handler is invoked
    And the Kubernetes HTTP/2 watch request is closed
    And no further events are delivered to the pod list view model
    And the AsyncResource state transitions to "idle"

  Scenario: Multiple views reading the same @Observable property update in one render pass
    Given the sidebar and the status bar both read the "activeContext" @Observable property
    When the operator switches to a different cluster context
    Then both the sidebar and the status bar display the new context name
    And both updates occur in the same SwiftUI render pass
    And the @Observable change notification fires exactly once for the property change

  Scenario: Combine is not used for new view-to-domain bindings
    Given the project is inspected for new Swift files added since ADR-0034 adoption
    When a code search is run for ObservableObject, @Published, AnyCancellable
    And PassthroughSubject in files under Sources/AppShell and Sources/UI
    Then the search returns zero matches in those directories
    And all new view models use @Observable with for-try-await domain port consumption

# DDD role: BehaviouralSpecification
Feature: Icon catalog — consistent SF Symbols iconography
  As an operator using K8sManager on macOS
  I want every Kubernetes resource kind, status state, and action
  to be represented by a consistent, accessible, and native-looking symbol
  So that I can identify resources at a glance without relying on text labels alone
  And so that the application integrates naturally with macOS visual conventions

  Background:
    Given the application has launched and connected to a cluster
    And the #IconCatalog (ADR-0028) is fully loaded from the app bundle
    And the cluster has at least one resource of each catalogued kind

  # ── Scenario 1: Kind symbol consistency across sidebar / list / detail ──────────

  Scenario: Pod symbol is consistent across sidebar, resource list row, and detail header
    When the operator selects "Workloads" in the sidebar
    And the operator selects "Pods" in the sidebar
    Then the sidebar row for "Pods" displays the custom symbol "k8s.pod"
    And every row in the resource list displays "k8s.pod" in its leading icon area
    When the operator selects the first Pod in the resource list
    Then the detail pane header displays "k8s.pod" at 24 pt
    And the sidebar row, list row, and detail header all use the same symbol name "k8s.pod"
    And the symbol in each location uses renderingMode "hierarchical"
    And each symbol has accessibilityLabel "Kind: Pod"

  Scenario: Deployment, StatefulSet, and DaemonSet each render their distinct custom symbols
    When the operator navigates to the Deployments resource list
    Then every list row leading icon uses symbol "k8s.deployment" with accessibilityLabel "Kind: Deployment"
    When the operator navigates to the StatefulSets resource list
    Then every list row leading icon uses symbol "k8s.statefulset" with accessibilityLabel "Kind: StatefulSet"
    When the operator navigates to the DaemonSets resource list
    Then every list row leading icon uses symbol "k8s.daemonset" with accessibilityLabel "Kind: DaemonSet"
    And none of the three symbol names equal each other

  Scenario: Native SF Symbols kinds render correct stock symbols
    When the operator navigates to the Services resource list
    Then every list row leading icon uses symbol "antenna.radiowaves.left.and.right" with accessibilityLabel "Kind: Service"
    When the operator navigates to the ConfigMaps resource list
    Then every list row leading icon uses symbol "doc.text" with accessibilityLabel "Kind: ConfigMap"
    When the operator navigates to the Secrets resource list
    Then every list row leading icon uses symbol "lock.doc" with accessibilityLabel "Kind: Secret"
    When the operator navigates to the Nodes resource list
    Then every list row leading icon uses symbol "server.rack" with accessibilityLabel "Kind: Node"

  # ── Scenario 2: Status badges use fill variants in ApiServerHealth widget ────────

  Scenario: Status badges in the ApiServerHealth widget use filled symbol variants
    Given the menu bar tray popover is open
    And the ApiServerHealth widget is visible in the tray popover
    When the active cluster API server is reachable and responding within SLA
    Then the health badge displays symbol "checkmark.circle.fill"
    And the badge uses renderingMode "palette" with primary tint from token "statusHealthy"
    And the badge accessibilityLabel is "Status: Healthy"
    When the active cluster API server returns 5xx errors
    Then the health badge displays symbol "xmark.octagon.fill"
    And the badge uses renderingMode "palette" with primary tint from token "statusError"
    And the badge accessibilityLabel is "Status: Error"
    When the active cluster API server is unreachable but was recently reachable
    Then the health badge displays symbol "exclamationmark.triangle.fill"
    And the badge uses renderingMode "palette" with primary tint from token "statusWarning"
    And the badge accessibilityLabel is "Status: Warning"

  # ── Scenario 3: Palette rendering mode resolves correctly in light and dark ──────

  Scenario: Palette rendering mode adapts symbol color layers to the active color scheme
    Given the operator's color scheme is set to "Light" in System Settings
    When a resource with status "error" is displayed in the resource list
    Then the status badge primary layer resolves to the light hex value of token "statusError"
    And the status badge secondary layer resolves to the light hex value of token "surfaceBackground"
    And the contrast ratio between the primary and secondary layers is at least 3.0
    When the operator switches the color scheme to "Dark" in System Settings
    Then the status badge primary layer resolves to the dark hex value of token "statusError"
    And the status badge secondary layer resolves to the dark hex value of token "surfaceBackground"
    And the contrast ratio between the primary and secondary layers is at least 3.0 in dark mode

  # ── Scenario 4: Custom symbols are available offline (bundle-embedded) ───────────

  Scenario: Custom k8s.* symbols render without a network connection
    Given the device has no active network interface (airplane mode)
    And no cluster connection is established
    When the operator opens the application
    Then the sidebar renders the cluster navigation item using symbol "rectangle.3.group"
    When the operator opens the empty state onboarding screen
    Then the application icon glyph renders using custom symbol "k8s.helm.wheel"
    And no network request is issued to resolve any symbol
    And the custom symbols "k8s.pod", "k8s.deployment", "k8s.statefulset", "k8s.daemonset", "k8s.helm.wheel" all render without error
    And no missing-symbol placeholder (question mark in a box) appears anywhere in the UI

  # ── Scenario 5: Accessibility label present on every symbol rendered ─────────────

  Scenario: Every symbol in the icon catalog has a non-empty accessibilityLabel at every call site
    When an automated accessibility audit runs against the main window
    Then every Image element backed by a symbol from #IconCatalog declares a non-empty accessibilityLabel
    And no Image element passes an empty string or the raw symbol name as its accessibilityLabel
    When VoiceOver is enabled and the operator navigates the sidebar via keyboard
    Then VoiceOver announces "Navigation: Cluster" for the cluster navigation item
    And VoiceOver announces "Kind: Pod" for the Pods sidebar item
    And VoiceOver announces "Status: Healthy" for a healthy resource status badge
    And VoiceOver announces "Action: View Logs" for the logs toolbar button
    When VoiceOver is enabled and the operator navigates the resource list
    Then VoiceOver announces the resource kind, name, namespace, and status for each row
    And the kind portion of the announcement uses the catalogued accessibilityLabel string

  # ── Scenario 6: symbolEffect .pulse applied to pending status ────────────────────

  Scenario: Pending status badge animates with .pulse effect while resource is transitioning
    Given the operator is viewing a resource list that contains a Pod in "Pending" state
    When the Pod is in "Pending" status and the reduce-motion preference is off
    Then the status badge for that Pod uses symbol "clock.fill"
    And the "clock.fill" symbol has a .symbolEffect(.pulse) modifier applied
    And the pulse animation is visible (non-static rendering)
    When the Pod transitions from "Pending" to "Running"
    Then the status badge changes to "checkmark.circle.fill" with a one-shot .symbolEffect(.bounce)
    And after the bounce completes the status badge is static (no continuous animation)

  Scenario: symbolEffect .pulse is suppressed when reduce-motion is enabled
    Given the operator has enabled "Reduce Motion" in System Settings > Accessibility
    And a Pod in "Pending" state is visible in the resource list
    When the resource list renders the pending Pod's status badge
    Then the status badge displays "clock.fill" statically (no animation)
    And no .symbolEffect modifier is applied to any symbol in the resource list
    And the symbol still uses renderingMode "palette" with primary tint from "statusPending"

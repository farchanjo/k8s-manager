# DDD role: ChaosScenario
# Bounded context: terminal_session
# Failure mode: orphan debug pod after app crash (F15 variant)
# References: ADR-0041, ADR-0028

Feature: Orphaned debug pod detected after app crash prompts operator to delete
  As a cluster operator
  I need the app to detect debug pods it created before a crash
  So that I am prompted to clean them up rather than leaving cluster resources stranded

  Background:
    Given the app created a debug pod "k8sm-debug-abc123" in namespace "kube-system" 65 minutes ago
    And the app crashed after creating the pod (before completing or deleting it)
    And the debug pod is still running in the cluster

  @chaos @concurrency
  Scenario: Relaunch detects orphan debug pod older than 60-second grace period
    When the app relaunches and reconciles its debug-pod registry
    Then the app queries the cluster for pods with label "app.kubernetes.io/managed-by=k8smanager-debug"
    And it finds "k8sm-debug-abc123" with age 65 minutes (beyond the 60-second grace period)
    And the app surfaces a non-blocking prompt "Orphaned debug pod found: k8sm-debug-abc123 — delete it?"

  @chaos @concurrency
  Scenario: Operator confirms deletion and orphan pod is removed
    Given the orphan prompt is displayed for "k8sm-debug-abc123"
    When the operator clicks "Delete"
    Then the app issues a DELETE request for pod "k8sm-debug-abc123" in namespace "kube-system"
    And the pod is deleted
    And the prompt is dismissed
    And the metric "debug_pod_orphan_deleted_total" increments by 1

  @chaos @concurrency
  Scenario: Debug pod within 60-second grace period is NOT treated as orphan on relaunch
    Given the app created a debug pod "k8sm-debug-fresh" 30 seconds before the crash
    When the app relaunches within the 60-second grace window
    Then "k8sm-debug-fresh" is NOT listed as an orphan
    And no deletion prompt is shown for "k8sm-debug-fresh"

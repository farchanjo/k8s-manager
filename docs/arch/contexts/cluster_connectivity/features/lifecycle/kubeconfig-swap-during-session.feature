# DDD role: BehaviouralSpecification
# Bounded context: cluster_connectivity
# References: ADR-0002, ADR-0003, ADR-0011, ADR-0025, ADR-0029

Feature: Kubeconfig file modification detected via kqueue during an active session
  As a platform engineer
  I want K8sManager to detect kubeconfig changes without disrupting the current session
  So that newly added contexts appear after a context-switch without re-launching the app

  Background:
    Given a ClusterSessionActor for cluster "prod-us-east-1" is in "connected" state
    And the kubeconfig at "~/.kube/config" was last modified at timestamp T=0
    And a kqueue EVFILT_VNODE filter is registered on the kubeconfig file descriptor

  @happy @lifecycle
  Scenario: Kubeconfig mtime changes are detected without disrupting the active session
    Given the current active cluster is "prod-us-east-1" with watch streams running
    When an external process modifies "~/.kube/config" changing its mtime to T+10s
    Then the kqueue EVFILT_VNODE event fires with NOTE_WRITE flag
    And the session for "prod-us-east-1" continues running using its cached credential set
    And the cached kubeconfig for the active session is NOT reloaded immediately
    And no watch stream is interrupted
    And no SessionDegraded event is emitted for "prod-us-east-1"

  @happy @lifecycle
  Scenario: Newly added context becomes visible on next context-switch
    Given the operator has modified "~/.kube/config" to add a new context "dev-local"
    And the kqueue event has fired signalling the file modification
    When the operator opens the cluster switcher UI
    Then the cluster list reflects the updated kubeconfig including "dev-local"
    And the original "prod-us-east-1" session remains in "connected" state
    And the operator can activate "dev-local" to open a new ClusterSessionActor for it

  @failure @lifecycle
  Scenario: Kubeconfig removed while sessions are active
    Given ClusterSessionActors are running for "prod-us-east-1" and "staging-eu-west"
    When an external process deletes "~/.kube/config"
    Then the kqueue EVFILT_VNODE event fires with NOTE_DELETE flag
    And the application emits a KubeconfigMissing notification to the operator
    And all existing ClusterSessionActors continue running using their cached credentials
    And no new ClusterSessionActor can be opened until a kubeconfig is restored

  @failure @lifecycle
  Scenario: Kubeconfig replaced with a structurally invalid file
    Given the active session for "prod-us-east-1" is in "connected" state
    When "~/.kube/config" is overwritten with invalid YAML content
    Then the kqueue event fires and the application attempts to parse the new file
    And parsing returns a kubeconfig validation error
    And the running ClusterSessionActor for "prod-us-east-1" continues using cached state
    And the application shows a non-dismissible banner: "kubeconfig parse error — context list unavailable"
    And no new sessions can be opened until the file is corrected

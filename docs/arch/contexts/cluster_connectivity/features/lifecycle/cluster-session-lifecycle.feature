# DDD role: BehaviouralSpecification
# Bounded context: cluster_connectivity
# References: ADR-0002, ADR-0007, ADR-0011, ADR-0018, ADR-0025, ADR-0026

Feature: Cluster session cold-boot and multi-launch restoration
  As a platform engineer
  I want cluster sessions to survive app restarts and handle multiple active sessions
  So that my workflow context is preserved across launches and cluster state is isolated

  Background:
    Given the application binary has been installed and is signed with Developer ID
    And no ClusterSessionActor instances are running
    And the filesystem root is "~/.config/k8smanager/"

  @happy @lifecycle
  Scenario: Cold launch with no previous state opens a blank shell
    Given no "view_state.json" exists for any cluster under "clusters/"
    And no active context record exists in "storage.sqlite3"
    When the application launches for the first time
    Then the application creates "~/.config/k8smanager/" with permissions 0700
    Then the application creates "storage.sqlite3" with WAL journal mode
    And the shell renders in the loading state with no active cluster selected
    And no ClusterSessionActor is spawned
    And no SessionOpened event is emitted

  @happy @lifecycle
  Scenario: Second launch restores pinned cluster sessions in parallel
    Given the previous session had pinned clusters "prod-us-east-1" and "staging-eu-west"
    And "view_state.json" exists for both clusters under their respective "clusters/<id>/" directories
    And "storage.sqlite3" contains the active context identifier for "prod-us-east-1"
    When the application launches
    Then a parallel TaskGroup spawns ClusterSessionActors for both "prod-us-east-1" and "staging-eu-west"
    And each actor loads its "view_state.json" and restores sidebar expansion and namespace filter
    And each actor emits a "connecting" event followed by a "connected" event
    And the active cluster is restored to "prod-us-east-1"
    And the total number of NIO event-loop threads does not exceed 4 on a 4-core host

  @happy @lifecycle
  Scenario: Manual disconnect while other sessions remain active
    Given ClusterSessionActors are running for "prod-us-east-1" and "staging-eu-west"
    And "prod-us-east-1" has 2 active watch streams and 3 idle HTTP connections
    When the operator manually disconnects "prod-us-east-1"
    Then the ClusterSessionActor for "prod-us-east-1" transitions to "terminating"
    And the watch stream registry for "prod-us-east-1" is emptied
    And the HTTPClient for "prod-us-east-1" is shut down within 500 milliseconds
    And the EventLoopGroup for "prod-us-east-1" is stopped
    And a SessionTerminated event with reason "operator-requested" is published
    And the ClusterSessionActor for "staging-eu-west" remains in "connected" state
    And its HTTPClient pool and watch stream registry are unchanged

  @failure @lifecycle
  Scenario: App quit during active session closes all sessions within deadline
    Given ClusterSessionActors are running for "prod-us-east-1" and "staging-eu-west"
    And each has at least one active port-forward listener
    When the application receives applicationWillTerminate
    Then all ClusterSessionActors transition to "terminating"
    And all port-forward listeners are torn down within 500 milliseconds of the quit signal
    And all EventLoopGroups call syncShutdownGracefully before process exit
    And no dangling kqueue file descriptors remain open after exit

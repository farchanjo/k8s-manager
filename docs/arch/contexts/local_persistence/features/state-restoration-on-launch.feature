Feature: State restoration on cold launch

  As a platform engineer using K8sManager
  I want the application to restore my previous session state on cold launch
  So that I can resume work without manually re-opening clusters, terminals, and port-forwards,
  and so that sensitive prompts (terminals, port-forwards, storage migration) require my explicit consent.

  Background:
    Given the application binary is at version "1.0.0"
    And the storage root is "~/.config/k8smanager/"

  Scenario: Cold launch loads a RestorationManifest and restores pinned cluster sessions
    Given a storage file exists at "~/.config/k8smanager/storage.sqlite3"
    And the RestorationManifest records activeContextId "aaaaaaaa-aaaa-7aaa-aaaa-aaaaaaaaaaaa"
    And the RestorationManifest records pinnedClusterContextIds ["cccccccc-cccc-7ccc-cccc-cccccccccccc", "dddddddd-dddd-7ddd-dddd-dddddddddddd"]
    And per-cluster view_state.json files exist for both pinned cluster ids
    When the application starts
    Then PersistenceActor opens "~/.config/k8smanager/storage.sqlite3" with journal_mode WAL
    And PersistenceActor assembles a RestorationManifest with schemaVersion 1
    And a ClusterSessionActor is spawned for "cccccccc-cccc-7ccc-cccc-cccccccccccc"
    And a ClusterSessionActor is spawned for "dddddddd-dddd-7ddd-dddd-dddddddddddd"
    And both sessions are spawned in a parallel TaskGroup without blocking the UI thread
    And the active context is set to "aaaaaaaa-aaaa-7aaa-aaaa-aaaaaaaaaaaa"
    And each session's view state is loaded from its view_state.json

  Scenario: Cold launch presents an opt-in prompt before reopening terminal sessions
    Given the RestorationManifest has openTerminalSessions ["t1uuid-0000-7000-a000-000000000001", "t1uuid-0000-7000-a000-000000000002", "t1uuid-0000-7000-a000-000000000003"]
    When the application starts
    Then the application presents a RestorationPrompt of kind "reopen_terminals"
    And the prompt text states "Reopen 3 terminals from last session?"
    When the operator accepts the prompt
    Then ClusterSessionActor reopens the 3 terminal sessions
    And a RestorationPrompt record with accepted true is persisted to storage.sqlite3
    When an alternative operator declines the same prompt
    Then no terminal sessions are reopened
    And a RestorationPrompt record with accepted false is persisted to storage.sqlite3

  Scenario: Cold launch presents an opt-in prompt before reopening port-forward listeners
    Given the RestorationManifest has openPortForwards ["pf000001-0000-7000-a000-000000000001", "pf000001-0000-7000-a000-000000000002"]
    When the application starts
    Then the application presents a RestorationPrompt of kind "reopen_port_forwards"
    And the prompt text states "Reopen 2 port-forwards from last session?"
    When the operator accepts the prompt
    Then ClusterSessionActor re-establishes the 2 port-forward listeners
    And a RestorationPrompt record with accepted true is persisted to storage.sqlite3
    When an alternative operator declines the same prompt
    Then no port-forward listeners are opened
    And a RestorationPrompt record with accepted false is persisted to storage.sqlite3

  Scenario: First-run migration offers to move legacy storage to the new path
    Given a storage file exists at "~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3"
    And no file exists at "~/.config/k8smanager/storage.sqlite3"
    When the application starts for the first time with the new path convention
    Then the application presents a RestorationPrompt of kind "migrate_storage_path"
    And the prompt payload contains sourcePath "~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3"
    And the prompt payload contains targetPath "~/.config/k8smanager/storage.sqlite3"
    When the operator accepts the migration prompt
    Then the storage file is moved (not copied) to "~/.config/k8smanager/storage.sqlite3"
    And the legacy directory "~/Library/Application Support/com.archanjo.K8sManager/" is left in place but empty
    And a RestorationPrompt record with kind "migrate_storage_path" and accepted true is persisted
    And subsequent launches do not show the migration prompt

  Scenario: Declining the migration prompt starts a fresh database at the new path
    Given a storage file exists at "~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3"
    And no file exists at "~/.config/k8smanager/storage.sqlite3"
    When the application starts and the operator declines the migration prompt
    Then a fresh "~/.config/k8smanager/storage.sqlite3" is initialised with the current schema
    And the legacy file at "~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3" is left untouched
    And a RestorationPrompt record with kind "migrate_storage_path" and accepted false is persisted
    And the application starts with an empty RestorationManifest

  Scenario: Fresh install on a machine with no prior K8sManager data
    Given no storage file exists at "~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3"
    And no storage file exists at "~/.config/k8smanager/storage.sqlite3"
    When the application starts for the first time
    Then no migration prompt is presented
    Then "~/.config/k8smanager/" is created with permissions 0700
    And "~/.config/k8smanager/storage.sqlite3" is initialised with journal_mode WAL
    And the RestorationManifest has empty pinnedClusterContextIds, openTerminalSessions, and openPortForwards
    And the active context is absent
    And the application presents the onboarding welcome screen

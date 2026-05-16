# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (reveal orchestration), DomainService (dockerconfig parser, tls parser), Aggregate (SecretAuditEvent)
# Context: resource_browser
# Related ADRs: ADR-0063 (Secret data reveal/hide), ADR-0047 (Audit chain HMAC keychain), ADR-0012 (Mutating operations policy)
Feature: Secret key reveal and hide

  Background:
    Given the operator has the K8sManager application in the foreground
    And a cluster named "prod-aks" is connected and active
    And the Secret detail drawer is open for Secret "db-credentials" in namespace "payments"
    And the Secret has type "Opaque"
    And the Secret data map contains keys "DB_PASSWORD", "DB_HOST", and "API_TOKEN"
    And the audit HMAC key is present in the macOS Keychain per ADR-0047

  Scenario: Reveal single key shows value and writes audit entry
    Given all three keys are displayed as masked placeholder rows
    When the operator clicks the eye icon for key "DB_PASSWORD"
    Then the "DB_PASSWORD" row displays the decoded UTF-8 value inline
    And the eye icon label for "DB_PASSWORD" changes to "Hide value for key DB_PASSWORD"
    And the "DB_HOST" and "API_TOKEN" rows remain masked
    And a "secret_reveal_audit" entry is written with the following shape:
      - action: "reveal"
      - secretName: "db-credentials"
      - namespace: "payments"
      - keyName: "DB_PASSWORD"
      - secretType: "Opaque"
      - clusterId: the UUIDv7 of the "prod-aks" cluster context
      - the entry carries a valid HMAC-SHA256 chain link derived from the previous entry digest
    And the decoded value of "DB_PASSWORD" does not appear in any field of the audit entry

  Scenario: dockerconfigjson key reveals parsed auths table with password masked by default
    Given the Secret has type "kubernetes.io/dockerconfigjson"
    And the Secret data key ".dockerconfigjson" encodes a valid docker config JSON with two registries:
      - registry "registry.io" with username "alice" and password "s3cr3t-a"
      - registry "ghcr.io" with username "bob" and password "s3cr3t-b"
    When the operator clicks the eye icon for key ".dockerconfigjson"
    Then the drawer renders a structured auths table with two rows:
      - row 1: registry "registry.io", username "alice", password masked with an eye icon
      - row 2: registry "ghcr.io", username "bob", password masked with an eye icon
    And the raw JSON string is not shown
    And a "secret_reveal_audit" entry is written with keyName ".dockerconfigjson" and action "reveal"
    When the operator clicks the eye icon for the password cell in the "registry.io" row
    Then the "registry.io" password cell displays "s3cr3t-a"
    And a second "secret_reveal_audit" entry is written with keyName ".dockerconfigjson.auths.registry.io.password" and action "reveal"
    And the "ghcr.io" password cell remains masked

  Scenario: Clipboard copy emits toast confirmation and clears pasteboard after 90 seconds
    Given the operator has revealed the value of key "API_TOKEN"
    When the operator clicks the copy icon for key "API_TOKEN"
    Then the system pasteboard contains the decoded value of "API_TOKEN"
    And a toast notification appears with the message "Copied to clipboard — will clear in 90 s"
    And a "secret_reveal_audit" entry is written with action "clipboard-copy" and keyName "API_TOKEN"
    And the decoded value of "API_TOKEN" does not appear in any field of the audit entry
    When 90 seconds elapse without another application overwriting the pasteboard
    Then the system pasteboard no longer contains the previously copied value
    When 90 seconds elapse after a copy and a second application has written a different value to the pasteboard in the interim
    Then the system pasteboard retains the second application's value and is not cleared by K8sManager

  Scenario: Auto-hide after application window loses focus for 60 seconds
    Given the operator has revealed the values of keys "DB_PASSWORD" and "API_TOKEN"
    When the K8sManager application window loses focus
    And 60 continuous seconds elapse without the window regaining focus
    Then the "DB_PASSWORD" row is re-masked and shows the placeholder
    And the "API_TOKEN" row is re-masked and shows the placeholder
    And a "secret_reveal_audit" entry is written for each re-masked key with action "auto-hide"
    When the application window regains focus immediately after the auto-hide
    Then all key rows remain masked
    And the eye icons are available for the operator to reveal values again

  Scenario: tls.key is never auto-revealed on Secret detail open
    Given the Secret has type "kubernetes.io/tls"
    And the Secret data map contains keys "tls.crt" and "tls.key"
    When the Secret detail drawer is opened
    Then both "tls.crt" and "tls.key" rows are displayed as masked placeholder rows
    And neither value is decoded or rendered without an explicit eye-icon click
    When the operator clicks the eye icon for key "tls.crt"
    Then the "tls.crt" row shows the PEM block in a monospaced block
    And a certificate metadata summary is rendered below the PEM block showing subject, issuer, validity dates, and serial number
    And the "tls.key" row remains masked
    And a "secret_reveal_audit" entry is written with keyName "tls.crt" and action "reveal"
    When the operator does not click the eye icon for "tls.key"
    Then "tls.key" remains masked for the full lifetime of the drawer session

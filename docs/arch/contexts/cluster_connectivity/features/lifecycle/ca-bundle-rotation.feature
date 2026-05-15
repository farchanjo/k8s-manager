# DDD role: BehaviouralSpecification
# Bounded context: cluster_connectivity
# References: ADR-0002, ADR-0007, ADR-0011, ADR-0018, ADR-0025

Feature: Cluster CA bundle rotation recovery
  As a platform engineer
  I want the adapter to detect TLS failures caused by CA rotation and re-read the kubeconfig CA
  So that sessions recover after a cluster CA is rotated without requiring app restart

  Background:
    Given a ClusterSessionActor for cluster "prod-us-east-1" is in "connected" state
    And the cluster's CA is pinned in the HTTPClient configuration at session open time
    And the cluster's Kubernetes API server has just rotated its serving certificate

  @happy @lifecycle
  Scenario: TLS handshake failure triggers CA re-read and connection recovery
    Given the new API server certificate is signed by a new CA added to "~/.kube/config"
    When the adapter issues the next HTTP request to the API server
    Then the TLS handshake fails with "certificate verify failed" (the old CA no longer validates)
    And the adapter detects the TLS error as a potentially CA-related failure
    And the adapter re-reads the kubeconfig at "~/.kube/config" to extract the new CA bundle
    And the HTTPClient for "prod-us-east-1" is reconfigured with the new CA
    And the adapter retries the failed request once
    And the retry succeeds with the new CA
    And the ClusterSessionActor remains in "connected" state

  @failure @lifecycle
  Scenario: CA rotation fails because kubeconfig still carries the old CA
    Given the kubeconfig has NOT yet been updated with the new CA
    When the adapter re-reads the kubeconfig after the TLS failure
    Then the extracted CA is still the old one that does not validate the new server certificate
    And the retry also fails with "certificate verify failed"
    And the ClusterSessionActor transitions to "degraded"
    And a SessionDegraded event with reason "tls-ca-mismatch" is published
    And the application surfaces a banner: "TLS CA validation failed for prod-us-east-1 — update kubeconfig"

  @failure @lifecycle
  Scenario: Expired client certificate causes rejection before CA check
    Given the HTTPClient for "prod-us-east-1" uses a client certificate that expired yesterday
    When the adapter issues any request to the API server
    Then the server returns a 401 Unauthorized or TLS alert
    And the adapter distinguishes client-cert expiry from CA mismatch using the TLS error code
    And a SessionDegraded event with reason "client-cert-expired" is published
    And the application surfaces a banner specific to client certificate expiry

  @security @lifecycle
  Scenario: CA bundle from kubeconfig is never written to disk or logged
    Given the adapter re-reads the kubeconfig and extracts a new CA bundle (PEM block)
    When the CA bundle is applied to the HTTPClient configuration
    Then the CA PEM bytes are held only in the in-memory SecCertificate representation
    And no log line contains PEM-encoded certificate data
    And no file under "~/.config/k8smanager/" contains the CA PEM bytes

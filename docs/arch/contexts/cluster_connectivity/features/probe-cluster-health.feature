# DDD role: Feature
# Bounded context: cluster_connectivity
Feature: Probe cluster health

  As an operator
  I want to see at a glance which of my clusters are reachable
  So that I do not waste time switching to a context that cannot serve me

  Background:
    Given a kubeconfig has been loaded successfully
    And the application has not yet probed any cluster

  Scenario: A reachable cluster reports "reachable" with latency
    Given a cluster "dev-cluster" whose API server returns 200 on "/readyz"
    When the ClusterHealthProbe is run for "dev-cluster"
    Then the HealthStatus.state is "reachable"
    And the HealthStatus.latencyMillis is a non-negative integer
    And the HealthStatus.detail is empty

  Scenario: A cluster with an expired client certificate reports "unauthorized"
    Given a cluster "old-prod" whose client certificate has expired
    When the ClusterHealthProbe is run for "old-prod"
    Then the HealthStatus.state is "unauthorized"
    And the HealthStatus.detail mentions "certificate"
    And the HealthStatus.detail does not include the certificate body

  Scenario: A cluster whose API server is offline reports "unreachable"
    Given a cluster "edge-1" whose API server endpoint refuses connections
    When the ClusterHealthProbe is run for "edge-1"
    Then the HealthStatus.state is "unreachable"
    And the HealthStatus.latencyMillis is absent
    And the HealthStatus.detail mentions the failure mode

  Scenario: A cluster requiring an exec plugin succeeds when the plugin is installed
    Given a cluster "eks-stg" uses an exec plugin "aws"
    And the "aws" binary is on PATH and returns a valid ExecCredential
    When the ClusterHealthProbe is run for "eks-stg"
    Then the HealthStatus.state is "reachable"

  Scenario: A cluster requiring an exec plugin fails gracefully when the plugin is missing
    Given a cluster "gke-prd" uses an exec plugin "gke-gcloud-auth-plugin"
    And the "gke-gcloud-auth-plugin" binary is not on PATH
    When the ClusterHealthProbe is run for "gke-prd"
    Then the HealthStatus.state is "unreachable"
    And the HealthStatus.detail includes the installHint from the kubeconfig exec block

  Scenario: A cluster with insecureSkipTLSVerify is probed without trust pinning but warns
    Given a cluster "kind-local" sets insecureSkipTLSVerify=true
    When the ClusterHealthProbe is run for "kind-local"
    Then the HealthStatus.state is "reachable"
    And a warning is recorded in the load report
    And no credential material is cached beyond the probe lifetime

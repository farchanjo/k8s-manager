# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (cluster discovery), DomainService (kubeconfig materialisation)
# Context: cluster_connectivity
# Related ADRs: ADR-0055 (Cloud provider cluster discovery), ADR-0018 (Native cloud credential resolution), ADR-0054 (Welcome tab)
Feature: AWS EKS cluster discovery

  As an operator managing EKS clusters on AWS
  I want K8sManager to enumerate my EKS clusters using my current AWS credentials
  So that I can import kubeconfig entries without running aws eks update-kubeconfig
  And without having the AWS CLI installed

  Background:
    Given the application is running with no subprocess execution entitlements
    And the welcome tab is visible with the "Add Clusters from AWS" action available
    And the operator has not yet imported any EKS cluster

  Scenario: Discover and import EKS clusters using default credential chain
    Given the environment contains valid AWS credentials for account "123456789012"
    And the credential chain resolves to an IAM principal with permissions:
      - "eks:ListClusters"
      - "eks:DescribeCluster"
      - "ec2:DescribeRegions"
    And the AWS account contains two EKS clusters named "prod-cluster" and "staging-cluster"
    And both clusters are in region "us-east-1"
    When the operator activates "Add Clusters from AWS" on the welcome tab
    And the region picker is pre-populated and the operator confirms "us-east-1"
    And the operator selects both "prod-cluster" and "staging-cluster" in the discovery preview
    And the operator confirms the import
    Then two KubeconfigEntry values are written to the in-memory kubeconfig aggregate
    And the context name for "prod-cluster" follows the ARN format
      """
      arn:aws:eks:us-east-1:123456789012:cluster/prod-cluster
      """
    And the exec block for each entry uses command "aws" with args:
      """
      [eks, get-token, --cluster-name, <cluster-name>, --region, us-east-1]
      """
    And both clusters appear in the cluster strip under the "EKS" provider section
    And no subprocess was invoked during the entire discovery and import sequence

  Scenario: No AWS credentials configured — actionable error is surfaced
    Given no AWS credentials are present in the environment variables
    And no "~/.aws/credentials" file exists
    When the operator activates "Add Clusters from AWS" on the welcome tab
    Then no discovery API call is made
    And an error sheet is presented with the message:
      """
      No AWS credentials found. Configure credentials via environment variables,
      ~/.aws/credentials, or an IAM role before retrying.
      """
    And the error sheet contains a "Learn more" link to the AWS credentials documentation
    And the welcome tab remains open and the operator can retry without restarting the application

  Scenario: Region filter scopes discovery to specified regions only
    Given the environment contains valid AWS credentials
    And the credential chain resolves with permission "eks:ListClusters"
    And the AWS account contains EKS clusters in regions "us-east-1", "eu-west-1", and "ap-southeast-2"
    When the operator activates "Add Clusters from AWS" on the welcome tab
    And the operator selects only "eu-west-1" in the region picker
    And the operator confirms discovery
    Then the discovery adapter calls "eks:ListClusters" only for region "eu-west-1"
    And clusters from "us-east-1" and "ap-southeast-2" are not included in the discovery preview
    And the preview shows only the clusters located in "eu-west-1"

  Scenario: Partial import — one cluster describe fails, others succeed
    Given the environment contains valid AWS credentials
    And the AWS account contains three EKS clusters: "alpha", "beta", "gamma" all in "us-east-1"
    And "eks:DescribeCluster" for "beta" returns a network timeout error
    When the operator activates "Add Clusters from AWS" on the welcome tab
    And the region picker is confirmed with "us-east-1"
    And the operator selects all three clusters in the discovery preview and confirms import
    Then KubeconfigEntry values are written for "alpha" and "gamma"
    And no KubeconfigEntry is written for "beta"
    And a DiscoveryWarning is emitted identifying "beta" as the failed descriptor
    And the warning is visible in the application notification stream
    And the operator is not blocked from using "alpha" and "gamma" immediately

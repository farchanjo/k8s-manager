# DDD role: BehaviouralSpecification
Feature: Topology Graph Dashboard

  The Topology Graph dashboard renders an interactive, zoomable node-edge graph
  of Kubernetes resource relationships. Edges represent owner references (Pod to
  ReplicaSet to Deployment), service selector matches (Service to Endpoints to
  Pods), and Helm release ownership (HelmRelease to managed resources). Clicking
  a node opens the corresponding detail scope. The graph supports zoom, pan, and
  PNG export.

  Background:
    Given the operator has launched K8S-Manager
    And a Kubernetes context "production-aks" is selected and reachable
    And the operator has selected TopologyGraphScope in the sidebar

  Scenario: Owner references render as directed edges from Pod to ReplicaSet to Deployment
    Given namespace "payments" contains a Deployment "payments-api" with 3 replicas
    And each replica pod has ownerReference pointing to ReplicaSet "payments-api-7d9b8c"
    And the ReplicaSet has ownerReference pointing to Deployment "payments-api"
    When the TopologyGraphWidget renders with rootRef = Deployment/payments/payments-api
    Then the graph displays three nodes: Deployment, ReplicaSet, and 3 Pod nodes
    And directed edges connect each Pod → ReplicaSet → Deployment
    And edge direction arrows point from child to owner (Pod → ReplicaSet → Deployment)

  Scenario: Service selector relationships render as edges from Service to Endpoints to Pods
    Given Service "payments-gateway" in namespace "payments" has selector "app=payments-api"
    And 3 pods match the selector and appear in the Endpoints object
    When the TopologyGraphWidget renders with includeServices = true
    Then the graph includes a Service node "payments-gateway" connected to an Endpoints node
    And the Endpoints node is connected to the 3 matching Pod nodes
    And the edge type is labeled "selects" for Service → Pod relationships

  Scenario: Helm release ownership edges connect HelmRelease to all managed resources
    Given a Helm release "payments-stack" in namespace "payments" manages 7 resources:
      a Deployment, a Service, a ConfigMap, an HPA, a ServiceAccount, a Role, and a RoleBinding
    When the TopologyGraphWidget renders with includeHelmReleases = true
    Then the graph includes a HelmRelease node "payments-stack"
    And directed edges connect "payments-stack" → each of the 7 managed resource nodes
    And the edge type is labeled "manages" for HelmRelease → resource relationships

  Scenario: Clicking a topology node opens its detail scope
    Given the topology graph displays a Pod node "payments-api-7d9b8c-xk2pw" in namespace "payments"
    When the operator clicks the Pod node
    Then a DrillToScope event is emitted with targetScope = PodDetailScope(namespace="payments", podName="payments-api-7d9b8c-xk2pw")
    And the sidebar scope picker switches to "Pod Detail"
    And the PodDetail dashboard renders for that pod

  Scenario: Graph renders within 2 seconds for a cluster with 500 nodes at depth limit 3
    Given the cluster has 500 pods, 80 ReplicaSets, 40 Deployments, and 30 Services
    And the TopologyGraphWidget is configured with depthLimit = 3
    When the graph data is fetched and the layout is computed
    Then the interactive graph is displayed within 2 seconds of the scope selection
    And nodes beyond depth 3 from the rootRef are not rendered

  Scenario: Operator can export the topology graph as PNG
    Given the topology graph is fully rendered with all nodes and edges visible
    When the operator activates the "Export PNG" action in the TopologyGraph widget toolbar
    Then a PNG file named "topology-graph-production-aks-2026-05-15.png" is saved to the Downloads folder
    And the exported image captures the current zoom level and visible node set

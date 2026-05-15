# DDD role: BehaviouralSpecification
Feature: Start port-forward session
  As a cluster operator using K8sManager
  I want to open a port-forward tunnel from a local TCP port to a Pod port
  So that I can interact with in-cluster services using local tools
  without exposing those services via Ingress or LoadBalancer

  Background:
    Given a kubeconfig context "dev-cluster" is active
    And the cluster is reachable and responds to API requests
    And the Kubernetes API server is version 1.31 or later
    And the WebSocket upgrade endpoint negotiates subprotocol "portforward.k8s.io"

  Scenario: Forward a single port from a Pod on matching local and remote ports
    Given a Pod "postgres-0" exists in namespace "data"
    And the Pod phase is "Running"
    And port 5432 is exposed by the Pod
    When the operator creates a port-forward session for Pod "postgres-0" in namespace "data"
    And the operator specifies a PortMapping with localPort 5432 and remotePort 5432
    Then a PortForwardSession is created with status "opening"
    And the target is a PodTarget with namespace "data" and podName "postgres-0"
    And the session status transitions to "running"
    And a ListenerBound event is emitted with effectiveLocalPort 5432
    And a SessionOpened event is emitted
    And a local TCP listener is bound on 127.0.0.1:5432
    And the operator can connect a PostgreSQL client to 127.0.0.1:5432

  Scenario: Resolve a Service to a backing Pod before opening the tunnel
    Given a Service "redis" exists in namespace "cache" with selector "app=redis"
    And a Pod "redis-primary-7d9f8c-abc12" exists in namespace "cache" with label "app=redis"
    And the Pod phase is "Running"
    And port 6379 is exposed by the Pod
    When the operator creates a port-forward session targeting Service "redis" in namespace "cache"
    And the operator specifies a PortMapping with localPort 6379 and remotePort 6379
    Then PortForwardManagerActor calls ServiceEndpointReaderPort to resolve Service "redis"
    And the ServiceTarget.resolvedPodName is set to "redis-primary-7d9f8c-abc12"
    And the WebSocket upgrade URL references Pod "redis-primary-7d9f8c-abc12"
    And the session transitions to "running"
    And a ListenerBound event is emitted confirming effectiveLocalPort 6379
    And the tunnel forwards traffic to port 6379 on "redis-primary-7d9f8c-abc12"

  Scenario: Local port 0 results in a kernel-assigned dynamic port
    Given a Pod "api-server-xyz" exists in namespace "backend"
    And the Pod phase is "Running"
    And port 8080 is exposed by the Pod
    When the operator creates a port-forward session for Pod "api-server-xyz"
    And the operator specifies a PortMapping with localPort 0 and remotePort 8080
    Then the PortMapping is submitted with localPort 0
    And after bind(2) the kernel assigns an ephemeral port (e.g. 52341)
    And the PortMapping.localPort in the aggregate is updated to the assigned port
    And a ListenerBound event is emitted with effectiveLocalPort equal to the assigned port
    And the assigned port is displayed in the UI beside the tunnel entry

  Scenario: Local port already in use reports a bind error
    Given a Pod "web-app-001" exists in namespace "frontend"
    And the Pod phase is "Running"
    And port 3000 is exposed by the Pod
    And another process on the local machine is already listening on 127.0.0.1:3000
    When the operator creates a port-forward session for Pod "web-app-001"
    And the operator specifies a PortMapping with localPort 3000 and remotePort 3000
    Then the bind(2) call fails with EADDRINUSE
    And a SessionFailed event is emitted with errorCode "local_bind_failed"
    And the detail field mentions port 3000 without including any credential material
    And the session status is set to "error"
    And no WebSocket connection is attempted

  Scenario: Multiple remote ports are forwarded within a single session
    Given a Pod "observability-stack-0" exists in namespace "monitoring"
    And the Pod phase is "Running"
    And the Pod exposes port 9090 (Prometheus) and port 3000 (Grafana)
    When the operator creates a port-forward session for Pod "observability-stack-0"
    And the operator specifies two PortMappings:
      | localPort | remotePort | portIndex |
      | 9090      | 9090       | 0         |
      | 3000      | 3000       | 1         |
    Then the WebSocket upgrade URL includes "ports=9090&ports=3000"
    And two local TCP listeners are bound, one per PortMapping
    And a ListenerBound event is emitted for portIndex 0 with effectiveLocalPort 9090
    And a ListenerBound event is emitted for portIndex 1 with effectiveLocalPort 3000
    And a SessionOpened event is emitted once for the session
    And frames for port 9090 carry portIndex byte 0x00 in the wire header
    And frames for port 3000 carry portIndex byte 0x01 in the wire header

  Scenario: Binding on 0.0.0.0 triggers a network-exposure warning in the UI
    Given a Pod "grpc-service-abc" exists in namespace "services"
    And the Pod phase is "Running"
    And port 50051 is exposed by the Pod
    When the operator creates a port-forward session for Pod "grpc-service-abc"
    And the operator sets bindAddress to "0.0.0.0" and localPort 50051 and remotePort 50051
    Then PortForwardManagerActor binds the listener on 0.0.0.0:50051
    And a ListenerBound event is emitted with isNetworkExposed set to true
    And the application layer surfaces a warning to the operator:
      "This tunnel is accessible from your local network, not just localhost."
    And the session transitions to "running" after the operator acknowledges the warning

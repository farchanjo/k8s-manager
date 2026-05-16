// DDD role: ValueObject
// Bounded context: metrics_observability
// Compile-time catalog of curated PromQL templates shipped with the application.
// Placeholders in expr strings use curly-brace notation:
//   {namespace}  — Kubernetes namespace of the selected resource
//   {podName}    — name of the selected Pod
//   {node}       — name of the selected Node

package metrics_observability

// A single curated PromQL template entry.
#CuratedQuery: {
	// Unique slug identifier for this query. Lowercase with underscores.
	// Used as the `templateKey` consumed by `metrics_policy.rego`
	// (ADR-0058, ADR-0059). Adding a new id REQUIRES updating
	// `curated_template_keys` in the policy in lockstep.
	id: string & =~"^[a-z][a-z0-9_]*$"

	// Human-readable display name shown in the UI.
	name: string & !=""

	// PromQL expression template. May contain placeholders in curly-brace
	// notation:
	//   {namespace}, {podName}, {node}, {workload}
	// Placeholder values are validated by `metrics_policy.rego` against the
	// ADR-0044 whitelist regex `^[a-zA-Z0-9._-]{1,63}$` before substitution.
	expr: string & !=""

	// Functional category for grouping in the UI.
	category: "cpu" | "memory" | "network" | "disk" | "api_server" | "workload_health"

	// Default time range template applied when the user has not customised the window.
	// start_rfc3339 and end_rfc3339 are template strings; the client substitutes
	// "now-{offset}" notation at render time.
	default_range: {
		start_rfc3339: string
		end_rfc3339:   string
		step_seconds:  int & >=1
	}

	// Default resolution step in seconds.
	default_step_seconds: int & >=1
}

// The compile-time catalog. 12 curated entries covering CPU, memory, network,
// disk, API server, and workload health.
#CuratedQueryCatalog: {
	queries: [
		// --- CPU ---
		{
			id:       "pod_cpu_usage_seconds"
			name:     "Pod CPU Usage (rate 2m)"
			expr:     "rate(container_cpu_usage_seconds_total{namespace=\"{namespace}\",pod=~\"{podName}\",container!=\"\"}[2m])"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "node_cpu_busy_percent"
			name:     "Node CPU Busy %"
			expr:     "1 - avg(rate(node_cpu_seconds_total{mode=\"idle\",node=\"{node}\"}[2m]))"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},

		// --- Memory ---
		{
			id:       "pod_memory_working_set_bytes"
			name:     "Pod Memory Working Set"
			expr:     "container_memory_working_set_bytes{namespace=\"{namespace}\",pod=~\"{podName}\",container!=\"\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "node_memory_available_bytes"
			name:     "Node Memory Available"
			expr:     "node_memory_MemAvailable_bytes{node=\"{node}\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},

		// --- Network ---
		{
			id:       "pod_network_rx_bytes_rate"
			name:     "Pod Network Receive Rate"
			expr:     "rate(container_network_receive_bytes_total{namespace=\"{namespace}\",pod=~\"{podName}\"}[2m])"
			category: "network"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "pod_network_tx_bytes_rate"
			name:     "Pod Network Transmit Rate"
			expr:     "rate(container_network_transmit_bytes_total{namespace=\"{namespace}\",pod=~\"{podName}\"}[2m])"
			category: "network"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},

		// --- Disk ---
		{
			id:       "node_disk_io_utilization"
			name:     "Node Disk I/O Utilization"
			expr:     "rate(node_disk_io_time_seconds_total{node=\"{node}\"}[2m])"
			category: "disk"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},

		// --- API Server ---
		{
			id:       "apiserver_request_rate"
			name:     "API Server Request Rate"
			expr:     "rate(apiserver_request_total[1m])"
			category: "api_server"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "apiserver_5xx_rate"
			name:     "API Server 5xx Error Rate"
			expr:     "rate(apiserver_request_total{code=~\"5..\"}[1m])"
			category: "api_server"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "apiserver_p99_latency"
			name:     "API Server P99 Latency (s)"
			expr:     "histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket[5m])) by (le))"
			category: "api_server"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},

		// --- Workload Health ---
		{
			id:       "workload_replicas_available"
			name:     "Workload Available Replicas"
			expr:     "kube_deployment_status_replicas_available{namespace=\"{namespace}\"} or kube_statefulset_replicas{namespace=\"{namespace}\"}"
			category: "workload_health"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "workload_restart_rate"
			name:     "Container Restart Rate (15m)"
			expr:     "rate(kube_pod_container_status_restarts_total{namespace=\"{namespace}\"}[15m])"
			category: "workload_health"
			default_range: {
				start_rfc3339: "now-60m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},

		// -------------------------------------------------------------------
		// ADR-0058 — Node detail drawer four-series chart
		// -------------------------------------------------------------------
		{
			id:       "node_drawer_cpu_usage"
			name:     "Node CPU Usage"
			expr:     "rate(node_cpu_usage_seconds_total{node=~\"^{node}$\",mode!=\"idle\"}[2m])"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "node_drawer_cpu_requests"
			name:     "Node CPU Requests"
			expr:     "sum(kube_pod_container_resource_requests{resource=\"cpu\",node=~\"^{node}$\"})"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "node_drawer_cpu_allocatable"
			name:     "Node CPU Allocatable"
			expr:     "kube_node_status_allocatable_cpu_cores{node=~\"^{node}$\"}"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "node_drawer_cpu_capacity"
			name:     "Node CPU Capacity"
			expr:     "kube_node_status_capacity_cpu_cores{node=~\"^{node}$\"}"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "node_drawer_memory_usage"
			name:     "Node Memory Usage"
			expr:     "node_memory_MemTotal_bytes{node=~\"^{node}$\"} - node_memory_MemAvailable_bytes{node=~\"^{node}$\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "node_drawer_memory_requests"
			name:     "Node Memory Requests"
			expr:     "sum(kube_pod_container_resource_requests{resource=\"memory\",node=~\"^{node}$\"})"
			category: "memory"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "node_drawer_memory_allocatable"
			name:     "Node Memory Allocatable"
			expr:     "kube_node_status_allocatable_memory_bytes{node=~\"^{node}$\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "node_drawer_memory_capacity"
			name:     "Node Memory Capacity"
			expr:     "kube_node_status_capacity_memory_bytes{node=~\"^{node}$\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},

		// -------------------------------------------------------------------
		// ADR-0058 — Pod detail drawer chart series
		// -------------------------------------------------------------------
		{
			id:       "pod_drawer_cpu_usage"
			name:     "Pod CPU Usage"
			expr:     "rate(container_cpu_usage_seconds_total{namespace=~\"^{namespace}$\",pod=~\"^{podName}$\",container!=\"\"}[2m])"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "pod_drawer_cpu_requests"
			name:     "Pod CPU Requests"
			expr:     "kube_pod_container_resource_requests{namespace=~\"^{namespace}$\",pod=~\"^{podName}$\",resource=\"cpu\"}"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "pod_drawer_cpu_limits"
			name:     "Pod CPU Limits"
			expr:     "kube_pod_container_resource_limits{namespace=~\"^{namespace}$\",pod=~\"^{podName}$\",resource=\"cpu\"}"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "pod_drawer_memory_usage"
			name:     "Pod Memory Usage"
			expr:     "container_memory_working_set_bytes{namespace=~\"^{namespace}$\",pod=~\"^{podName}$\",container!=\"\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "pod_drawer_memory_requests"
			name:     "Pod Memory Requests"
			expr:     "kube_pod_container_resource_requests{namespace=~\"^{namespace}$\",pod=~\"^{podName}$\",resource=\"memory\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "pod_drawer_memory_limits"
			name:     "Pod Memory Limits"
			expr:     "kube_pod_container_resource_limits{namespace=~\"^{namespace}$\",pod=~\"^{podName}$\",resource=\"memory\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},

		// -------------------------------------------------------------------
		// ADR-0058 — Workload aggregate chart series (Deployment / STS / DS)
		// -------------------------------------------------------------------
		{
			id:       "workload_drawer_cpu_aggregate"
			name:     "Workload CPU (aggregate)"
			expr:     "sum(rate(container_cpu_usage_seconds_total{namespace=~\"^{namespace}$\"}[2m])) by (pod)"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "workload_drawer_memory_aggregate"
			name:     "Workload Memory (aggregate)"
			expr:     "sum(container_memory_working_set_bytes{namespace=~\"^{namespace}$\"}) by (pod)"
			category: "memory"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "workload_drawer_replicas_deployment"
			name:     "Deployment Replicas Available"
			expr:     "kube_deployment_status_replicas_available{namespace=~\"^{namespace}$\",deployment=~\"^{workload}$\"}"
			category: "workload_health"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "workload_drawer_replicas_statefulset"
			name:     "StatefulSet Replicas Ready"
			expr:     "kube_statefulset_status_replicas_ready{namespace=~\"^{namespace}$\",statefulset=~\"^{workload}$\"}"
			category: "workload_health"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},
		{
			id:       "workload_drawer_replicas_daemonset"
			name:     "DaemonSet Replicas Ready"
			expr:     "kube_daemonset_status_number_ready{namespace=~\"^{namespace}$\",daemonset=~\"^{workload}$\"}"
			category: "workload_health"
			default_range: {
				start_rfc3339: "now-50m"
				end_rfc3339:   "now"
				step_seconds:  30
			}
			default_step_seconds: 30
		},

		// -------------------------------------------------------------------
		// ADR-0059 — Resource-list row mini-bar batch queries
		// -------------------------------------------------------------------
		{
			id:       "node_list_cpu_usage"
			name:     "Node CPU Usage (list mini-bar)"
			expr:     "rate(node_cpu_usage_seconds_total{mode!=\"idle\"}[2m])"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
		{
			id:       "node_list_cpu_capacity"
			name:     "Node CPU Capacity (list mini-bar)"
			expr:     "kube_node_status_capacity_cpu_cores"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
		{
			id:       "node_list_memory_usage"
			name:     "Node Memory Usage (list mini-bar)"
			expr:     "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes"
			category: "memory"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
		{
			id:       "node_list_memory_capacity"
			name:     "Node Memory Capacity (list mini-bar)"
			expr:     "kube_node_status_capacity_memory_bytes"
			category: "memory"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
		{
			id:       "node_list_disk_usage"
			name:     "Node Disk Usage (list mini-bar)"
			expr:     "node_filesystem_size_bytes - node_filesystem_avail_bytes"
			category: "disk"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
		{
			id:       "node_list_disk_capacity"
			name:     "Node Disk Capacity (list mini-bar)"
			expr:     "node_filesystem_size_bytes"
			category: "disk"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
		{
			id:       "pod_list_cpu_usage"
			name:     "Pod CPU Usage (list mini-bar)"
			expr:     "rate(container_cpu_usage_seconds_total{namespace=~\"^{namespace}$\",container!=\"\"}[2m])"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
		{
			id:       "pod_list_cpu_request"
			name:     "Pod CPU Request (list mini-bar)"
			expr:     "kube_pod_container_resource_requests{namespace=~\"^{namespace}$\",resource=\"cpu\"}"
			category: "cpu"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
		{
			id:       "pod_list_memory_usage"
			name:     "Pod Memory Usage (list mini-bar)"
			expr:     "container_memory_working_set_bytes{namespace=~\"^{namespace}$\",container!=\"\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
		{
			id:       "pod_list_memory_request"
			name:     "Pod Memory Request (list mini-bar)"
			expr:     "kube_pod_container_resource_requests{namespace=~\"^{namespace}$\",resource=\"memory\"}"
			category: "memory"
			default_range: {
				start_rfc3339: "now-2m"
				end_rfc3339:   "now"
				step_seconds:  15
			}
			default_step_seconds: 15
		},
	]
}

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
	id: string & =~"^[a-z][a-z0-9_]*$"

	// Human-readable display name shown in the UI.
	name: string & !=""

	// PromQL expression template. May contain {namespace}, {podName}, {node} placeholders.
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
	]
}

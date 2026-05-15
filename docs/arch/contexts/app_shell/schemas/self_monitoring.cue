// DDD role: ValueObject
// DDD Role: AggregateRoot
// Context: app_shell / SelfMonitoring sub-domain
// Schema for app-level self-monitoring state, metric samples, and diagnostics bundle export.

package app_shell

// ---------------------------------------------------------------------------
// Shared constraints
// ---------------------------------------------------------------------------

#UUIDv7: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

#RFC3339: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

// ---------------------------------------------------------------------------
// #SelfMonitoringState — AggregateRoot
//
// Persisted under local_persistence key: app_shell/self_monitoring_state
// Restored on cold launch; written on preference change.
// ---------------------------------------------------------------------------

#SelfMonitoringState: {
	// Stable identity for this preference record.
	id: #UUIDv7

	// How often the SelfMonitoringSampler collects a snapshot.
	// Operator-configurable via Settings → Diagnostics.
	sampleIntervalSeconds: 1 | 5 | 15 | 30 | 60 | *5

	// When true, the "App self-monitoring" widget is shown in the menu bar tray.
	// Off by default; operator enables via Settings → Diagnostics.
	surfaceInTray: bool | *false

	// Duration of the in-memory ring buffer (minutes).
	// At 5 s interval and 60 min retention: 720 samples ≈ 100 KB.
	retentionMinutes: (int & >=1 & <=1440) | *60

	// When true, the DiagnosticsBundleExporter is permitted to access
	// the SQLite persistence layer for 24 h historical export.
	exportEnabled: bool | *true
}

// ---------------------------------------------------------------------------
// #SelfMetricSample — Entity
//
// One snapshot collected by SelfMonitoringSampler at a single timestamp.
// Fields that are unavailable in the App Sandbox degrade to -1 (sentinel).
// ---------------------------------------------------------------------------

#SelfMetricSample: {
	// ISO 8601 / RFC 3339 timestamp at which the sample was taken.
	timestampRFC3339: #RFC3339

	// Process CPU utilization as a percentage.
	// Source: mach_task_info(TASK_BASIC_INFO) — user + system time delta.
	// Range: 0.0 .. (100.0 × logical core count). -1 if unavailable.
	cpuUsagePercent: float64 & >=-1

	// Resident set size (physical memory footprint) in bytes.
	// Source: TASK_VM_INFO — phys_footprint.
	// -1 if unavailable.
	memoryRSSBytes: int & >=-1

	// Peak resident set size since process start, in bytes.
	// Source: TASK_VM_INFO — phys_footprint_peak.
	// -1 if unavailable.
	memoryPeakRSSBytes: int & >=-1

	// Current OS thread count for this process.
	// Source: mach_task_info(TASK_BASIC_INFO) — thread_count.
	// -1 if unavailable.
	threadCount: int & >=-1

	// Number of open file descriptors for this process.
	// Source: proc_pidinfo(PROC_PIDLISTFDS) for calling PID.
	// -1 if unavailable (App Sandbox restriction or entitlement missing).
	fileDescriptorCount: int & >=-1

	// Total network bytes received across all HTTPClient instances
	// (per-cluster counters summed). Monotonically increasing; UI
	// computes per-sample delta for KB/s display.
	networkBytesIn: int & >=0

	// Total network bytes sent across all HTTPClient instances.
	networkBytesOut: int & >=0

	// Number of active Kubernetes watch streams (AsyncStream objects
	// backed by open HTTP/2 connections) across all cluster sessions.
	// Source: instrumented atomic counter.
	activeWatchStreams: int & >=0

	// Number of active kubectl exec sessions (PTY-backed exec sessions).
	// Source: instrumented atomic counter.
	activeExecSessions: int & >=0

	// Number of active port-forward tunnels.
	// Source: instrumented atomic counter.
	activePortForwards: int & >=0

	// Number of active AI chat streams (streaming LLM response sessions).
	// Source: instrumented atomic counter.
	activeChatStreams: int & >=0

	// Combined size in bytes of storage.sqlite3 and its WAL file.
	// Source: stat() on both files; summed. -1 if unavailable.
	sqliteSizeBytes: int & >=-1

	// Aggregate size in bytes of all files under ~/.config/k8smanager/cache/.
	// Source: recursive stat() aggregate. -1 if unavailable.
	cacheSizeBytes: int & >=-1

	// Count of live Swift actor instances registered with SelfMonitoringRegistry.
	// Source: instrumented global atomic counter (actorCreated / actorDestroyed).
	// -1 if the registry has not been initialized.
	actorCount: int & >=-1

	// Number of active SwiftNIO EventLoopGroup instances.
	// One group is created per active cluster session.
	// Source: instrumented atomic counter.
	eventLoopGroupCount: int & >=0

	// kqueue events processed per second by the SwiftNIO event loop.
	// Source: instrumented TimeSeriesAccumulator hook on NIOPosix.SelectableEventLoop.
	// nil when the hook point is not available in the linked SwiftNIO version.
	kqueueEventsPerSecond?: float64 & >=0
}

// ---------------------------------------------------------------------------
// #DiagnosticsBundle — ValueObject
//
// Metadata record embedded as bundle-manifest.json inside every exported
// diagnostics zip. Created by DiagnosticsBundleExporter and never mutated
// after the bundle is sealed.
// ---------------------------------------------------------------------------

#DiagnosticsBundle: {
	// Stable UUIDv7 for this bundle; used for deduplication in support workflows.
	bundleId: #UUIDv7

	// RFC 3339 timestamp at which DiagnosticsBundleExporter sealed the zip.
	generatedAtRFC3339: #RFC3339

	// Number of #SelfMetricSample records included in metrics/self-metrics-24h.json.
	sampleCount: int & >=0

	// List of log file names included under logs/ inside the zip (after redaction).
	// Example: ["app.log.redacted", "crash.log.redacted"]
	logFilesIncluded: [...string]

	// Total uncompressed size in bytes of all bundle contents before zipping.
	totalSizeBytes: int & >=0

	// True when the log redactor ran and confirmed no credential patterns remain.
	// Always true in a successfully sealed bundle; the exporter aborts if false.
	redactionApplied: bool | *true
}

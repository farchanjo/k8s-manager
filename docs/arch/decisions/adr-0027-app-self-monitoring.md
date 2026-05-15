# ADR-0027 — App Self-Monitoring and Diagnostics

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — monitoring, diagnostics, self-monitoring, darwin, mach, performance

## Context and problem statement

K8sManager is a long-running macOS agent that manages connections to one or more Kubernetes
clusters, maintains SwiftNIO event loops, spawns exec sessions, opens port-forwards, and streams
watch events continuously. As the feature surface grows — chat AI sessions, metrics observability,
analytics dashboards — the risk of undetected resource leaks and unbounded memory growth increases.

Operators who run K8sManager throughout the day need visibility into the application's own health:
CPU load, resident memory, thread count, and the number of active background sessions (watch
streams, exec sessions, port-forwards, chat streams). Without this, they cannot distinguish
application misbehaviour from cluster-side problems, and support engineers cannot diagnose
regressions from field reports alone.

The problem: **K8sManager currently exposes no introspective view of its own runtime health to the
operator or to support workflows.**

---

## Decision drivers

- Operators need in-app visibility without external tooling (Instruments, Activity Monitor).
- Support engineers need reproducible diagnostic bundles from field reports.
- The analytics dashboard (ADR-0024) already provides a plugin model for metric scopes;
  self-monitoring should integrate naturally.
- The menu bar tray (ADR-0022) already surfaces cluster widgets; an opt-in app-health widget is
  architecturally consistent.
- Privacy: no telemetry is uploaded automatically; all data stays local unless the operator
  explicitly exports a bundle.
- Performance: the sampler must not perturb the workloads it measures. Sampling overhead must be
  negligible compared to normal background I/O.

---

## Considered options

### Option A — No in-app monitoring (status quo)

Operators use macOS Activity Monitor or Instruments to observe K8sManager's resource usage. No
changes to the application.

**Pros:**

- Zero implementation cost.
- No additional maintenance surface.

**Cons:**

- Activity Monitor cannot correlate CPU spikes with specific Kubernetes cluster sessions or watch
  stream counts.
- Instruments requires developer tooling and operator proficiency.
- Export / support workflow is manual and operator-burdened.
- Invisible resource leaks accumulate silently.

**Verdict:** Rejected. Unacceptable for daily-driver use and support workflows.

---

### Option B — External profiler integration (Instruments / Xcode Organizer)

Emit signposts and os_log points from K8sManager; operators or support engineers attach Instruments
via the Xcode Instruments UI.

**Pros:**

- Industry-standard tooling.
- No UI surface to build inside K8sManager itself.
- Rich flame graphs and allocation tracks.

**Cons:**

- Requires Xcode installed on the operator's machine; not a reasonable assumption for the target
  persona (platform engineer, not developer).
- Instruments sessions cannot be bundled and shared as a file without manual export steps.
- No live in-app display; operator must switch to a separate application.
- Signpost payloads require careful sanitization before sharing; no automated redaction path.

**Verdict:** Rejected as primary solution. `os_signpost` emission may complement the chosen option
but does not replace it.

---

### Option C — In-app diagnostics panel with sampler and bundle export (chosen)

Implement a `SelfMonitoringSampler` domain service that collects process and session metrics on a
configurable interval (default 5 s) using Darwin APIs (`mach_task_info`, `TASK_VM_INFO`,
`proc_pidinfo`). Metrics are accumulated in an in-memory ring buffer (default 60 min retention).
They are surfaced in three places:

1. **Settings → Diagnostics tab** — live counters and 60-min sparklines for CPU, memory, and
   network.
2. **Menu bar tray widget** — opt-in "App self-monitoring" widget (disabled by default).
3. **Analytics dashboard** — new `SelfMonitoring` scope preset (ADR-0024 scope extension).

A `DiagnosticsBundleExporter` domain service packages the ring buffer (last 24 h when persisted)
plus sanitized log files into a `.zip` bundle written to `~/.config/k8smanager/exports/`. Credential
material is stripped by the log redactor before the zip is sealed.

**Pros:**

- Operator never leaves the application to check resource health.
- Support workflow: one-click export with guaranteed redaction.
- Architecturally consistent with ADR-0022 (tray) and ADR-0024 (analytics scopes).
- Darwin APIs are stable and have negligible overhead at 5 s intervals.
- No external dependency; no network transmission.
- Configurable sample interval covers both debugging (1 s) and background monitoring (60 s) use
  cases.

**Cons:**

- Additional implementation surface; new DomainService, CUE schema, and Gherkin spec required.
- Ring buffer consumes memory proportional to retention × metric count. At 5 s interval and 60 min
  retention: 720 samples × ~17 fields ≈ ~100 KB — acceptable.
- Proc-level file-descriptor counting (`PROC_PIDLISTFDS`) and Swift actor counting are best-effort
  on sandboxed builds; degrade gracefully to −1 sentinel.

**Verdict:** Chosen. See decision below.

---

## Decision outcome

**Chosen option: Option C — in-app diagnostics panel with sampler and bundle export.**

K8sManager will implement a `SelfMonitoringSampler` service that polls process-level and
session-level metrics every 5 seconds (operator- configurable). Metrics are held in an in-memory
ring buffer and optionally persisted to SQLite for 24 h bundle export. The operator interacts with
the diagnostics surface exclusively through the application; no data leaves the machine unless the
operator triggers an explicit export.

### Consequences

Positive:

- Operators gain immediate visibility into K8sManager's health without external tooling.
- Support engineers receive reproducible, redacted bundles from field reports.
- The `SelfMonitoring` analytics scope integrates with the existing ADR-0024 plugin model at zero
  protocol cost.
- The opt-in tray widget follows the established ADR-0022 `#TrayMetricWidget` sum-type extension
  pattern.

Negative:

- Three new DomainService types and one new CUE aggregate are added to `app_shell`.
- The `DiagnosticsBundleExporter` must be tested for redaction completeness; a failed redaction
  aborts the export (fail-safe).
- `actorCount` and `kqueueEventsPerSecond` are instrumented counters, not OS-level APIs; they
  require discipline from all bounded context authors to register and deregister correctly.

### Confirmation

- `SelfMonitoringSampler` collects all 17 metric fields within 5 s of startup; fields that are
  unavailable in the App Sandbox return the sentinel value `-1`.
- A 60-minute test run at 5 s interval produces at most 720 samples and ring buffer does not exceed
  100 KB RSS overhead.
- `DiagnosticsBundleExporter` redaction is verified by a test suite that exercises each of the 8
  mandatory patterns with a synthetic log line:
  - Rule 1: a line `Authorization: Bearer abc123.ABC_def/+=-xyz` is redacted to
    `Authorization: Bearer [REDACTED]`.
  - Rule 2: a line `token: k8s-aws-v1.abc123=` is redacted to `token: [REDACTED_K8S_AWS_TOKEN]`.
  - Rule 3: a line `Authorization: Basic dXNlcjpwYXNz` is redacted to `Authorization: [REDACTED]`.
  - Rule 4: a line `"refresh_token" : "my-refresh-secret"` is redacted to
    `"refresh_token": "[REDACTED]"`.
  - Rule 5: a line `"client_secret":"my-client-secret"` is redacted to
    `"client_secret": "[REDACTED]"`.
  - Rule 6: a line containing `eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.abc.def` is redacted to
    `[REDACTED_JWT]`.
  - Rule 7: a line containing `/Users/operator/.kube/config` is redacted to `[REDACTED_PATH]`. Each
    test asserts that the synthetic credential does not appear anywhere in the sealed zip.
- The Settings Diagnostics tab renders live counters and sparklines without blocking the main actor;
  measured by asserting 60 fps during a 60-second observation window.
- The opt-in tray widget is absent from the popover when
  `Settings > Diagnostics > Show app health in menu bar` is off; present when enabled.

## Metrics Collected

All metrics are sampled on the configured interval (default 5 s).

```
Metric field              Source API / mechanism                               Unit
------------------------  ---------------------------------------------------  --------
cpuUsagePercent           mach_task_info — TASK_BASIC_INFO                     percent
memoryRSSBytes            TASK_VM_INFO — phys_footprint                        bytes
memoryPeakRSSBytes        TASK_VM_INFO — phys_footprint_peak                   bytes
threadCount               mach_task_info — thread_count                        count
fileDescriptorCount       proc_pidinfo — PROC_PIDLISTFDS                       count
networkBytesIn            Per-HTTPClient instrumented counter (per-cluster +   bytes
                          total)
networkBytesOut           Per-HTTPClient instrumented counter (per-cluster +   bytes
                          total)
activeWatchStreams         Instrumented counter across all cluster sessions     count
activeExecSessions        Instrumented counter                                 count
activePortForwards        Instrumented counter                                 count
activeChatStreams          Instrumented counter                                 count
sqliteSizeBytes           stat(storage.sqlite3) + WAL file size                bytes
cacheSizeBytes            Aggregate stat of ~/.config/k8smanager/cache/        bytes
actorCount                Instrumented global atomic counter (actor            count
                          init/deinit)
eventLoopGroupCount       One per active cluster session; instrumented counter count
kqueueEventsPerSecond     Instrumented at SwiftNIO EventLoop level (optional)  events/s
```

Metrics that are unavailable in the App Sandbox context degrade to a sentinel value of `-1` and are
rendered as "unavailable" in the UI.

---

## Surfacing

### Settings → Diagnostics tab

- Live counter grid: all 17 fields refreshed every sample interval.
- Sparklines: CPU (%), memory RSS (MB), network in/out (KB/s) over the last 60 minutes at the
  configured sample interval resolution.
- Sample interval selector: 1 s / 5 s / 15 s / 30 s / 60 s (default 5 s).
- "Export diagnostics bundle" button — triggers `DiagnosticsBundleExporter`.

### Menu bar tray widget (opt-in)

- Off by default. Operator enables via Settings → Diagnostics → "Show app health in menu bar".
- Rendered as a `#TrayMetricWidget` variant in the tray popover.
- Displays: CPU %, memory RSS (MB), active sessions (watch + exec + port-forward + chat) as a
  compact chip row.
- Refresh cadence matches the global tray refresh interval (ADR-0022), not the self-monitoring
  sample interval.

### Analytics dashboard — `SelfMonitoring` scope (ADR-0024 extension)

- New preset scope identifier: `"self_monitoring"`.
- Exposes all 17 metric fields as time-series queryable within the analytics engine's existing query
  model.
- Default preset: CPU %, memory RSS, active sessions stacked area chart.

### Diagnostics bundle export

- Output path: `~/.config/k8smanager/exports/diagnostics-<yyyy-mm-dd-HH-MM-SS>.zip`
- Contents:
  - `metrics/self-metrics-24h.json` — last 24 h of `#SelfMetricSample` records (one JSON object per
    line, RFC 3339 timestamps).
  - `logs/app.log.redacted` — last 24 h of unified log output with all credential patterns scrubbed.
  - `bundle-manifest.json` — `#DiagnosticsBundle` metadata record.
- Redaction rules (applied before zip is sealed; LOW-02 expanded rule set). Rules are applied in the
  order listed. Each rule is compiled into an `NSRegularExpression`. Rules 1 through 6 are mandatory
  and cannot be disabled by the operator. Rules 7 and 8 are adjustable.
  1. Bearer token header values — pattern: `Bearer [A-Za-z0-9._~/+=-]{10,}` — replacement:
     `Bearer [REDACTED]`
  2. AWS EKS pre-signed token prefix — pattern: `k8s-aws-v1\.[A-Za-z0-9._~/-]+=*` — replacement:
     `[REDACTED_K8S_AWS_TOKEN]`
  3. Authorization header (Bearer, Basic, Token) — pattern:
     `Authorization:\s*(Bearer|Basic|Token)\s+[A-Za-z0-9+/=._~-]{10,}` — replacement:
     `Authorization: [REDACTED]`
  4. OAuth2 refresh token in JSON — pattern: `"refresh_token"\s*:\s*"[^"]+"` — replacement:
     `"refresh_token": "[REDACTED]"`
  5. OAuth2 / OIDC client secret in JSON — pattern: `"client_secret"\s*:\s*"[^"]+"` — replacement:
     `"client_secret": "[REDACTED]"`
  6. JWT-shaped bearer tokens (Base64url header `eyJ...`) — pattern: `eyJ[A-Za-z0-9+/=._-]{20,}` —
     replacement: `[REDACTED_JWT]`
  7. kubeconfig paths containing `/Users/` → replacement: `[REDACTED_PATH]`
  8. IPv4 addresses outside 127.0.0.0/8 and 10.0.0.0/8 optionally masked (operator opt-in; default:
     preserve)

- A failed redaction step aborts the export and surfaces an error to the operator. No partial bundle
  is written.

---

## Architecture

### Data flow

```mermaid
graph LR
    subgraph Sampler["SelfMonitoringSampler (DomainService)"]
        Darwin["Darwin APIs\nmach_task_info\nTASK_VM_INFO\nproc_pidinfo"]
        Counters["Instrumented counters\nwatch streams\nexec sessions\nport-forwards\nchat streams\nactors\nkqueue events"]
    end

    subgraph Buffer["MetricsBuffer (in-memory ring 60 min\n+ SQLite 24 h optional)"]
        Ring["Ring buffer\n720 samples @ 5 s"]
        Persist["SQLite WAL\napp_shell/self_metrics"]
    end

    subgraph Surfaces["Surfacing"]
        DiagnosticsView["Settings → Diagnostics\nlive counters + sparklines"]
        TrayWidget["Menu bar tray widget\n(opt-in)"]
        AnalyticsScope["Analytics dashboard\nSelfMonitoring scope"]
    end

    Exporter["DiagnosticsBundleExporter\n(DomainService)"]
    BundleZip["~/.config/k8smanager/\nexports/*.zip"]

    Darwin --> Sampler
    Counters --> Sampler
    Sampler --> Ring
    Ring --> Persist
    Ring --> DiagnosticsView
    Ring --> TrayWidget
    Ring --> AnalyticsScope
    Persist --> Exporter
    Exporter --> BundleZip
```

### Domain model

```
app_shell
 └─ SelfMonitoring sub-domain
     ├─ #SelfMonitoringState    (AggregateRoot) — preferences + runtime toggle
     ├─ #SelfMetricSample       (Entity)        — one snapshot at one timestamp
     ├─ #DiagnosticsBundle      (ValueObject)   — export metadata record
     ├─ SelfMonitoringSampler   (DomainService) — collects + feeds the ring
     └─ DiagnosticsBundleExporter (DomainService) — packages + redacts the zip
```

---

## Implementation Notes

### Sampling overhead

At a 5 s interval, each sample requires:

- One `task_info(TASK_BASIC_INFO)` call — < 1 µs.
- One `task_info(TASK_VM_INFO)` call — < 1 µs.
- One `proc_pidinfo(PROC_PIDLISTFDS)` call — < 100 µs (varies with fd count).
- Atomic reads from instrumented counters — < 100 ns each.
- One `stat` on the SQLite file — < 10 µs.
- One `stat` aggregate on `~/.config/k8smanager/cache/` — < 500 µs.

Total estimated per-sample cost: < 1 ms wall time. At 5 s interval this is < 0.02 % CPU overhead.

### Swift actor instrumentation contract

Every bounded context that creates a Swift actor type MUST call
`SelfMonitoringRegistry.shared.actorCreated()` in the actor's `init` and
`SelfMonitoringRegistry.shared.actorDestroyed()` in `deinit`. The registry holds an atomic `Int64`
counter. Failure to comply causes the reported `actorCount` to undercount; the counter never goes
negative (guarded by a `max(0, …)` floor).

### kqueue instrumentation

`kqueueEventsPerSecond` is derived from a `TimeSeriesAccumulator` fed by a hook in
`NIOPosix.SelectableEventLoop`. If the SwiftNIO version in use does not expose the hook point, the
field degrades to `nil` (optional in the CUE schema).

### Privacy and sandbox

The sampler runs entirely within the App Sandbox. No private framework APIs are called.
`proc_pidinfo(PROC_PIDLISTFDS)` is permitted for the calling process's own PID. If the sandbox
entitlement check fails at runtime, the field is set to `-1`.

All metric values are stored only in the in-process ring buffer and, when enabled, in the
application's own SQLite database. No metric value is transmitted over the network.

---

## Compliance

- **ADR-0022** (Menu bar tray): the tray widget follows the established `#TrayMetricWidget`
  extension point. No new refresh scheduler is introduced.
- **ADR-0024** (Analytics dashboard): `SelfMonitoring` is a new scope value in the existing scope
  enum; no protocol changes required.
- **ADR-0012** (Mutation safety): the diagnostics surface is read-only; no mutations are issued to
  any Kubernetes API.
- **ADR-0010** (Privacy): no metric data leaves the local machine automatically. The export bundle
  is initiated explicitly by the operator.

---

## More information

- ADR-0022 — Menu bar tray energy and lifecycle; opt-in tray widget follows the `#TrayMetricWidget`
  extension point.
- ADR-0024 — Analytics dashboard; `SelfMonitoring` is a new scope in the existing scope enum.
- ADR-0023 — Command palette; diagnostics export is accessible via the palette command catalog.
- ADR-0012 — Mutation safety; diagnostics surface is read-only.
- ADR-0010 — Local persistence; SQLite stores the 24 h ring buffer for the export bundle.
- `contexts/app_shell/schemas/self_monitoring.cue` — CUE schema for this bounded context.
- `contexts/app_shell/features/self-monitoring-diagnostics.feature` — acceptance scenarios.
- `contexts/app_shell/features/diagnostics-export.feature` — export bundle scenarios.

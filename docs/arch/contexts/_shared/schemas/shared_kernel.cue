// DDD role: ValueObject

package shared_kernel

// #UUIDv7 is the canonical identifier format for all entities in K8sManager.
// Time-ordered, sortable, and globally unique per RFC 9562 §5.7.
#UUIDv7: string & =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// #ClusterId uniquely identifies a Kubernetes cluster context loaded from kubeconfig.
// Generated as UUIDv7 on first kubeconfig parse. Stable across restarts.
#ClusterId: #UUIDv7

// #ContextId uniquely identifies a kubeconfig context entry (cluster + user + namespace triple).
// Generated as UUIDv7 on first load. One cluster may have multiple context entries.
#ContextId: #UUIDv7

// #ProviderProfileId uniquely identifies an LLM provider profile stored in local persistence.
#ProviderProfileId: #UUIDv7

// #EditorSessionId uniquely identifies an open editor session in the resource_browser context.
#EditorSessionId: #UUIDv7

// #KubeconfigPath is an absolute filesystem path to a kubeconfig YAML file.
// The constraint enforces POSIX absolute path form (leading slash).
#KubeconfigPath: string & =~"^/.*"

// #RFC3339 is a timestamp string conforming to RFC 3339 / ISO 8601 with time-zone designator.
// Millisecond precision is recommended; the pattern accepts optional fractional seconds.
#RFC3339: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

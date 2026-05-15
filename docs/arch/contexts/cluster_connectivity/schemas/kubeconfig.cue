// DDD role: AggregateRoot
package cluster_connectivity

import (
	"time"
)

// #Kubeconfig is the aggregate root for a single resolved kubeconfig
// source. It captures every cluster/user/context triple loaded from
// disk, plus the immutable provenance needed to detect external
// edits without holding a file handle open.
#Kubeconfig: {
	// id is a UUIDv7 generated when the aggregate is first loaded.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// sourcePath is the absolute, symlink-resolved path of the
	// source file. Used as the natural key when reconciling reloads.
	sourcePath!: =~"^/.+"

	// sourceMTimeRFC3339 is the file modification timestamp captured
	// at load time, in RFC3339 form. The application uses this to
	// detect external edits without polling the file.
	sourceMTimeRFC3339!: time.Format(time.RFC3339)

	// apiVersion mirrors the kubernetes config apiVersion field.
	apiVersion!: "v1"
	kind!:       "Config"

	// currentContext is the kubeconfig-level current-context value;
	// the application overrides it via context_navigation but
	// preserves the original for round-tripping diagnostics.
	currentContext!: string

	// clusters, users, and contexts are flat collections rather than
	// maps to preserve insertion order from the source file.
	clusters: [...#KubeconfigCluster]
	users: [...#KubeconfigUser]
	contexts: [...#KubeconfigContext]
}

// #KubeconfigCluster is the embedded cluster entry from kubeconfig.
// The richer domain #Cluster (cluster.cue) is derived from this
// entry by `cluster_connectivity.ClusterAssembler`.
#KubeconfigCluster: {
	name!:                     string
	server!:                   =~"^https?://"
	certificateAuthorityPath?: string
	certificateAuthorityData?: string
	insecureSkipTLSVerify?:    bool | *false
}

// #KubeconfigUser captures the raw user entry. Credential material
// is read-only and lives here only long enough to be transformed
// into an #AuthInfo value object.
#KubeconfigUser: {
	name!: string

	// Exactly one credential strategy must be present.
	clientCertificatePath?: string
	clientCertificateData?: string
	clientKeyPath?:         string
	clientKeyData?:         string
	token?:                 string
	tokenFile?:             string
	exec?: {
		apiVersion!: string
		command!:    string
		args?: [...string]
		env?: [...{name!: string, value!: string}]
		installHint?:       string
		provideClusterInfo: bool | *false
	}
}

// #KubeconfigContext binds a cluster name and a user name with an
// optional default namespace. The richer domain identifier
// (`ContextId` in the shared kernel) is the SHA-256 over
// `<sourcePath>::<name>` to remain stable across reloads.
#KubeconfigContext: {
	name!:      string
	cluster!:   string
	user!:      string
	namespace?: string | *"default"
}

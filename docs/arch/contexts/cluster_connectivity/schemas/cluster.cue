// DDD role: Entity
package cluster_connectivity

// #Cluster is the domain entity assembled from a #KubeconfigCluster
// plus the resolved certificate authority bytes. It is identified
// by a #ClusterId from the shared kernel and is mutable only
// through aggregate operations.
#Cluster: {
	// id is the shared-kernel ClusterId — stable across reloads as
	// long as the kubeconfig source path and cluster name are
	// unchanged. The id is the SHA-256 of `<sourcePath>::<name>`
	// truncated to 16 bytes and rendered as a UUIDv7-shaped string.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// name mirrors the kubeconfig `clusters[].name` field; it is
	// surfaced to the user as the cluster display name unless the
	// user explicitly renames it (renames live in context_navigation
	// as a separate ReadModel).
	name!: string

	// server is the API server URL. Always https in practice; http
	// is permitted for local development clusters (e.g., kind, k3d).
	server!: =~"^https?://"

	// caStrategy describes how the application trusts the cluster's
	// API server certificate.
	caStrategy!: #CAStrategy

	// insecureSkipTLSVerify SHOULD be false. When true, the
	// application surfaces a prominent warning in the UI and
	// declines to remember credentials beyond the current process.
	insecureSkipTLSVerify!: bool
}

// #CAStrategy is a sum type captured as a discriminated union of
// CUE structs. Exactly one branch is set at any time.
#CAStrategy: {
	// system uses the macOS trust store. Common for managed
	// clusters whose API server has a publicly-trusted certificate.
	kind!:    "system"
} | {
	// embedded carries inline PEM bytes decoded from
	// certificate-authority-data.
	kind!:    "embedded"
	pemData!: =~"^-----BEGIN CERTIFICATE-----"
} | {
	// referenced carries the absolute path of a CA bundle on disk
	// (certificate-authority).
	kind!: "referenced"
	path!: =~"^/.+"
}

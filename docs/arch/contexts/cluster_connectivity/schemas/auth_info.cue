// DDD role: ValueObject
package cluster_connectivity

// #AuthInfo is the immutable, in-memory representation of a
// resolved credential for a single Kubernetes context. It is
// derived from a #KubeconfigUser at probe time and discarded as
// soon as the resulting HTTP request completes. No instance of
// #AuthInfo ever lands on disk.
//
// Exactly one branch is populated for a given value.
#AuthInfo: #ClientCertAuth | #BearerTokenAuth | #ExecPluginAuth

// #ClientCertAuth is X.509 client-certificate auth, by far the
// most common form in development clusters.
#ClientCertAuth: {
	kind!: "client_cert"
	// certPEM and keyPEM hold the decoded bytes in memory. The
	// adapter never persists these.
	certPEM!: =~"^-----BEGIN CERTIFICATE-----"
	keyPEM!:  =~"^-----BEGIN (RSA |EC |)PRIVATE KEY-----"
}

// #BearerTokenAuth carries a static bearer token. The application
// reads the token only at request time; rotation is the operator's
// responsibility.
#BearerTokenAuth: {
	kind!:  "bearer_token"
	token!: string & =~"^[A-Za-z0-9._\\-]+$"
}

// #ExecPluginAuth carries the parameters needed to invoke an
// external exec credential plugin. The actual ExecCredential JSON
// is parsed by `cluster_connectivity.ExecPluginPort` and never
// stored in the aggregate.
#ExecPluginAuth: {
	kind!:       "exec_plugin"
	apiVersion!: =~"^client\\.authentication\\.k8s\\.io/v1(beta1|alpha1)?$"
	command!:    string
	args: [...string] | *[]
	env: [...{name!: string, value!: string}] | *[]
	provideClusterInfo: bool | *false
	installHint?:       string
}

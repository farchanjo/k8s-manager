// DDD role: AggregateRoot
package cluster_intelligence

// #MCPToolRegistry is the authoritative catalogue of tools the
// in-process MCP server advertises to the LLM. It is read-only
// at runtime; every entry is hard-coded in the cluster_intelligence
// domain target. New tools require an ADR before they land in this
// registry.
#MCPToolRegistry: {
	// version is bumped whenever the registry changes shape. The
	// host (assistant_chat) caches the registry by version.
	version!: int & >=1
	tools: [...#MCPTool]
}

// #MCPTool is one tool descriptor.
#MCPTool: {
	// name is snake_case and globally unique within this registry.
	name!:        =~"^[a-z][a-z0-9_]{0,63}$"
	description!: string
	// inputJSONSchema is a JSON Schema (draft-2020-12) literal.
	// The MCP server validates inputs against it before dispatch.
	inputJSONSchema!: string

	// kubernetesVerbs is the closed set of HTTP verbs this tool
	// may issue to the Kubernetes API. The policy gate denies any
	// verb outside this set.
	kubernetesVerbs!: [...#KubernetesVerb]

	// resources is the closed set of Kubernetes resource kinds this
	// tool may touch.
	resources!: [...string]

	// requiresPinnedContext is true when the tool needs a pinned
	// Kubernetes context. When false, the tool may accept an
	// explicit `contextId` argument.
	requiresPinnedContext!: bool

	// outputMaxBytes caps the JSON response body the MCP server
	// returns. Truncation marker is appended past this size.
	outputMaxBytes!: int & >=4096 & <=1048576 | *262144
}

#KubernetesVerb: "get" | "list" | "watch"

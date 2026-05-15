// DDD role: AggregateRoot
package assistant_chat

import (
	"strings"
	"time"
)

// #ChatSession is the aggregate root for one assistant conversation.
// Each session is bound to a single ProviderProfile at creation and
// optionally pinned to a Kubernetes context that biases the
// assistant's tool calls toward that cluster.
#ChatSession: {
	id!:                 =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	title!:              string & strings.MinRunes(1) & strings.MaxRunes(120)
	providerProfileId!:  =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// pinnedKubernetesContextId, when present, is the ContextId from
	// the shared kernel — biases the in-process MCP server to scope
	// tool calls to that cluster unless the assistant explicitly
	// names another.
	pinnedKubernetesContextId?: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	createdAtRFC3339!: time.Format(time.RFC3339)
	updatedAtRFC3339!: time.Format(time.RFC3339)

	// systemPrompt is the system message that opens every turn. It
	// is editable in the chat surface and persisted with the
	// session.
	systemPrompt!: string

	// status tracks whether the session is open in the UI, archived
	// from the sidebar, or marked for deletion.
	status!: "active" | "archived" | "trash"

	// turnCount is the number of completed user-assistant turn
	// pairs. Pure derived; persisted for ordering and pruning.
	turnCount!: int & >=0
}

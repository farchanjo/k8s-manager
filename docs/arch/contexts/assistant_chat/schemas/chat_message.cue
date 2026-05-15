// DDD role: Entity
package assistant_chat

import (
	"time"
)

// #ChatMessage is one persisted message inside a #ChatSession.
// Tool-use and tool-result content is captured as side records
// (#ToolCallRecord) rather than nested here so the message is a
// stable log entry independent of tool execution outcomes.
#ChatMessage: {
	id!:        =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	turn!:      int & >=0
	createdAtRFC3339!: time.Format(time.RFC3339)
	role!:      "system" | "user" | "assistant"
	// content holds the textual content as a single string. Tool
	// calls reference this message's id via #ToolCallRecord.parentMessageId.
	content!:   string
	// streaming captures the streamed-vs-complete state — true
	// while the assistant is still producing tokens, false on
	// finish or cancellation.
	streaming!: bool
	// finishReason mirrors the provider's final reason once
	// streaming completes.
	finishReason?: "stop" | "max_tokens" | "tool_use" | "error" | "cancelled"
	// usage is the accounting reported by the provider (if any).
	usage?: #UsageRecord
}

#UsageRecord: {
	promptTokens!:       int & >=0
	completionTokens!:   int & >=0
	cachedPromptTokens?: int & >=0
}

// #ToolCallRecord is a persisted entry of one tool-use round trip.
// Linked to its triggering assistant message via parentMessageId
// and to its result via the same callId.
#ToolCallRecord: {
	callId!:           =~"^[a-zA-Z0-9_\\-]{1,128}$"
	sessionId!:        =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	parentMessageId!:  =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
	toolName!:         =~"^[a-z][a-z0-9_]{0,63}$"
	requestedAtRFC3339!: time.Format(time.RFC3339)
	completedAtRFC3339?: time.Format(time.RFC3339)
	// argumentsJSON is the verbatim assembled arguments string the
	// model produced.
	argumentsJSON!: string
	// resultJSON is set when the tool completed; truncated to
	// 256 KiB by the MCP server (ADR-0009).
	resultJSON?: string
	// status enumerates the lifecycle of the tool call.
	status!: "requested" | "running" | "succeeded" | "denied_by_policy" | "failed" | "cancelled"
	// detail is operator-facing when status is denied or failed.
	detail?: string
}

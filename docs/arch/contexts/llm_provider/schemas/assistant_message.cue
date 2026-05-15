// DDD role: ValueObject
package llm_provider

// #AssistantMessage is the wire-agnostic representation of one turn
// in a conversation. The adapter translates this into Anthropic
// Messages API content blocks, OpenAI Chat Completions messages,
// or OpenAI-compatible variants.
#AssistantMessage: {
	role!:    "system" | "user" | "assistant" | "tool"
	content!: [...#MessagePart]
}

// #MessagePart is a sum type of the content shapes the providers
// commonly support. Adapters degrade gracefully when a provider
// does not support a shape (e.g., omitting redaction for providers
// without prompt caching).
#MessagePart: #TextPart | #ToolUsePart | #ToolResultPart

#TextPart: {
	kind!: "text"
	text!: string
	// cacheControl is honoured by providers that support prompt
	// caching (currently Anthropic via providerHints).
	cacheControl?: "ephemeral"
}

#ToolUsePart: {
	kind!:           "tool_use"
	callId!:         =~"^[a-zA-Z0-9_\\-]{1,128}$"
	name!:           string
	// jsonArguments is a UTF-8 JSON object encoded as a string.
	// Streaming providers may deliver this in chunks; the upstream
	// adapter buffers chunks and emits the full string here.
	jsonArguments!:  string
}

#ToolResultPart: {
	kind!:           "tool_result"
	callId!:         =~"^[a-zA-Z0-9_\\-]{1,128}$"
	// jsonResult is the UTF-8 JSON body returned by the tool. The
	// MCP server (see ADR-0009) caps this at 256 KiB and appends a
	// truncation marker when needed.
	jsonResult!:     string
	isError!:        bool
}

// #ToolDefinition is the schema advertised to the provider for the
// duration of one assistant turn. Tools are not persisted as
// aggregates here; they are derived from the MCP server's registry
// at request time.
#ToolDefinition: {
	name!:            =~"^[a-z][a-z0-9_]{0,63}$"
	description!:     string
	// inputJSONSchema is the JSON Schema (draft-2020-12) for the
	// tool inputs. Adapters translate it into the provider's tool
	// format.
	inputJSONSchema!: string
}

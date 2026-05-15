// DDD role: ValueObject
package llm_provider

// #AssistantStreamEvent is the normalised event shape emitted by
// every adapter. The assistant_chat context consumes these without
// caring which provider produced them.
#AssistantStreamEvent:
	#DeltaEvent |
	#ToolUseStartEvent |
	#ToolUseDeltaEvent |
	#ToolUseFinishEvent |
	#UsageEvent |
	#FinishEvent

// #DeltaEvent carries a chunk of assistant-visible text.
#DeltaEvent: {
	kind!: "delta"
	text!: string
}

// #ToolUseStartEvent announces a tool call. The full argument
// payload is delivered through subsequent #ToolUseDeltaEvent
// chunks and finalised by #ToolUseFinishEvent.
#ToolUseStartEvent: {
	kind!:   "tool_use_start"
	callId!: =~"^[a-zA-Z0-9_\\-]{1,128}$"
	name!:   string
}

#ToolUseDeltaEvent: {
	kind!:           "tool_use_delta"
	callId!:         =~"^[a-zA-Z0-9_\\-]{1,128}$"
	jsonChunk!:      string
}

#ToolUseFinishEvent: {
	kind!:            "tool_use_finish"
	callId!:          =~"^[a-zA-Z0-9_\\-]{1,128}$"
	totalArguments!:  string
}

// #UsageEvent is emitted at most once per stream when the provider
// reports usage. Adapters that do not report usage skip this event.
#UsageEvent: {
	kind!:             "usage"
	promptTokens!:     int & >=0
	completionTokens!: int & >=0
	// cachedPromptTokens is provider-specific; when absent assume 0.
	cachedPromptTokens?: int & >=0
}

// #FinishEvent marks the end of the stream.
#FinishEvent: {
	kind!:   "finish"
	reason!: "stop" | "max_tokens" | "tool_use" | "error" | "cancelled"
	// detail is populated only when reason is "error" or
	// "cancelled". MUST NOT include credential material.
	detail?: string
}

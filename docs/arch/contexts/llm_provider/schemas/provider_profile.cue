// DDD role: AggregateRoot
package llm_provider

import (
	"strings"
	"time"
)

// #ProviderProfile is the operator-facing unit of LLM configuration.
// One profile binds one provider kind to one model, with default
// sampling parameters and a reference to a Keychain-stored key.
#ProviderProfile: {
	// id is a UUIDv7. Stable for the life of the profile; rename
	// changes displayName, not id.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// displayName is the operator-chosen label. Free text, trimmed,
	// 1..80 characters.
	displayName!: string & strings.MinRunes(1) & strings.MaxRunes(80)

	kind!: "anthropic" | "openai" | "openai_compatible"

	// baseURL is required for openai_compatible; defaulted for the
	// other two. The default values are NOT stored in the profile;
	// the adapter resolves them at request time.
	baseURL?: =~"^https?://"

	// modelId is the provider-side model identifier (e.g.,
	// "claude-sonnet-4-6", "gpt-5.3", "qwen3:32b-instruct").
	modelId!: string & strings.MinRunes(1) & strings.MaxRunes(120)

	// keyAlias is a reference to a Keychain entry — NEVER the key
	// value. The adapter resolves the key on demand.
	keyAlias!: =~"^[a-z0-9][a-z0-9_\\-]*$"

	samplingDefaults!: #SamplingConfig

	createdAtRFC3339!: time.Format(time.RFC3339)
	updatedAtRFC3339!: time.Format(time.RFC3339)
}

// #SamplingConfig is an immutable value object capturing the
// sampling knobs the provider port understands.
#SamplingConfig: {
	temperature!:     float & >=0.0 & <=2.0
	topP?:            float & >0.0 & <=1.0
	topK?:            int & >0
	maxOutputTokens!: int & >0 & <=128000
	stopSequences: [...string] | *[]
	// providerHints carries provider-specific opt-ins (e.g.,
	// {"anthropic_prompt_caching": "ephemeral"},
	// {"openai_parallel_tool_calls": "false"}).
	providerHints: {[string]: string} | *{}
}

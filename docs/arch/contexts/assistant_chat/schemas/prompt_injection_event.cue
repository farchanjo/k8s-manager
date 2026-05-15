// DDD role: ValueObject
package assistant_chat

import "strings"

// #PromptInjectionSuspected is the domain event emitted by
// ContentFilterGateway when the content-filter layer (Layer 3 of the
// ADR-0048 defence-in-depth model) matches a denial pattern in a
// cluster-origin string before it is injected into the LLM context.
//
// The event is published on the DomainEventBusActor and also written
// to the diagnostics ring buffer (ADR-0027). It is intentionally
// low-cardinality: only the pattern ID and a short sanitized excerpt
// are captured — the full payload is never recorded to avoid
// inadvertently storing adversarial content in the event stream.
//
// Consumed by:
//   analytics_dashboard — for security-event telemetry widget.
//   app_shell           — for optional operator notification toast.
//
// References: ADR-0048 (LLM prompt injection defence).
#PromptInjectionSuspected: {
	// sessionId is the UUIDv7 of the active chat session in which the
	// suspected injection was detected.
	sessionId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// patternId is the identifier of the denial rule that matched,
	// e.g. "PI-001". Allows operators and telemetry to distinguish
	// which attack technique was attempted.
	patternId!: =~"^PI-[0-9]{3}$"

	// source is the Kubernetes resource identity from which the
	// cluster-origin payload was derived, in "<kind>/<name>" form,
	// e.g. "ConfigMap/my-config", "Pod/api-server-0".
	// Empty string when the source cannot be determined.
	source!: string & strings.MinRunes(0)

	// sanitizedExcerpt is the first 64 characters of the sanitized
	// (post-Layer-1) payload that triggered the denial. Provides
	// enough context for triage without storing the full adversarial
	// payload.
	sanitizedExcerpt!: string & =~"^.{0,64}$"

	// occurredAt is the RFC 3339 UTC timestamp at which ContentFilterGateway
	// detected the pattern match.
	occurredAt!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"

	// matchedPatterns is the complete set of pattern IDs that fired
	// for this payload. At least one entry is always present.
	matchedPatterns!: [...(=~"^PI-[0-9]{3}$")] & [_, ...]
}

// DDD role: ValueObject
// ADR: ADR-0031 — Loading states and async resource UX
//
// Defines the #AsyncResource sum type and associated presentation and
// empty-state value objects used across all async-data-loading views.
//
// Note on generics: CUE does not support generics. #AsyncResource is
// defined here with the value field typed as a top-level `_` (any type).
// In Swift this maps to the generic enum:
//
//   enum AsyncResource<T: Sendable>: Sendable {
//       case idle
//       case loading(startedAt: Date, progress: Double?)
//       case success(value: T, loadedAt: Date)
//       case failure(error: Error, occurredAt: Date, retryable: Bool)
//   }
//
// CUE constraints document the structural invariants; Swift enforces
// type-safety at compile time via the generic parameter.

package app_shell

import (
	"time"
	"strings"
)

// #AsyncResource represents the lifecycle of a single async operation
// that produces a value of type T for the UI. The discriminator field
// `state` identifies the active case.
//
// Exactly one of the case-specific sub-objects must be present;
// all others must be absent. This is a closed sum type — no additional
// cases are permitted without updating this schema.
#AsyncResource: {
	// state is the discriminator.
	state: "idle" | "loading" | "success" | "failure"

	// idle case: no operation in flight; initial or post-cancel state.
	// No additional fields.
	if state == "idle" {}

	// loading case: an async operation is in flight.
	if state == "loading" {
		// startedAtRFC3339 records when the operation was initiated.
		// Used to compute elapsed time for timeout detection.
		startedAtRFC3339: string & =~time.RFC3339

		// progress is optional. When present it is a double in [0.0, 1.0]
		// representing fractional completion. Used to drive a #progressBar
		// presentation. When absent, presentation defaults to skeleton or
		// spinner per #LoadingPresentation.
		progress?: float64 & >=0.0 & <=1.0
	}

	// success case: the operation completed and produced a value.
	if state == "success" {
		// value carries the loaded domain data. In Swift this is typed T.
		// In CUE it is represented as `_` (any). Constraints on the value
		// are expressed in the concrete schema that embeds #AsyncResource.
		value: _

		// loadedAtRFC3339 records when the value was received.
		loadedAtRFC3339: string & =~time.RFC3339
	}

	// failure case: the operation threw an error.
	if state == "failure" {
		// error is the localised error message surfaced to the operator.
		// MUST NOT contain credential material.
		error: string & strings.MinRunes(1)

		// occurredAtRFC3339 records when the error was caught.
		occurredAtRFC3339: string & =~time.RFC3339

		// retryable indicates whether the Retry button should be shown
		// in the ErrorState component. Set false for configuration errors
		// where retrying without operator intervention is meaningless.
		retryable: bool
	}
}

// #LoadingPresentation describes how a loading state is rendered.
// This value object is resolved by the view from the expected duration
// of the underlying operation, not by the domain layer.
#LoadingPresentation: {
	// presentation is the visual mode. Defaults to skeleton.
	//
	//   skeleton    — .redacted(reason: .placeholder) with fixed template
	//                 layout. Use when the structural layout is known and
	//                 estimated duration > 100 ms.
	//   shimmer     — .redacted + diagonal gradient animation overlay.
	//                 Use when layout is unknown or content-heavy, and
	//                 estimated duration > 100 ms.
	//   spinner     — indeterminate ProgressView (centered).
	//                 Use for quick operations estimated < 500 ms.
	//   progressBar — determinate ProgressView with a [0, 1] fraction.
	//                 Use when total unit count is known (batch apply,
	//                 file transfer).
	presentation: "skeleton" | "shimmer" | "spinner" | "progressBar"
	presentation: *"skeleton" | _

	// showAfterMillis is the 200 ms throttle threshold. The UI suppresses
	// the loading presentation until this many milliseconds have elapsed
	// since the operation was initiated. If the operation resolves before
	// this threshold, the presentation is never shown and there is no
	// visible flash.
	//
	// Default: 200 ms. Override to 0 to disable throttle (not recommended).
	showAfterMillis: int & >=0 & <=5000
	showAfterMillis: *200 | _
}

// #EmptyState describes the visual and interactive content shown when
// an AsyncResource reaches success but the value is an empty collection.
// EmptyState instances are authored statically per resource kind and
// context — they are never generated dynamically at the view layer.
#EmptyState: {
	// title is a concise statement of the absence, e.g.
	// "No pods in this namespace".
	title: string & strings.MinRunes(3) & strings.MaxRunes(80)

	// message provides context to help the operator understand why
	// the collection is empty and what they can do about it.
	message: string & strings.MinRunes(10) & strings.MaxRunes(300)

	// actionLabel is the label for the optional call-to-action button.
	// When absent, no button is rendered.
	actionLabel?: string & strings.MinRunes(2) & strings.MaxRunes(40)

	// actionType identifies the action the button triggers.
	//   configure — open the relevant configuration panel.
	//   retry     — re-run the domain operation that returned empty.
	//   reload    — reload the parent context (e.g. namespace switch).
	//
	// actionType must be present when actionLabel is present.
	if actionLabel != _|_ {
		actionType: "configure" | "retry" | "reload"
	}
}

// -----------------------------------------------------------------------
// Concrete empty-state instances used across the application
// -----------------------------------------------------------------------

// EmptyStatePodsInNamespace is shown when watchPods returns an empty list.
EmptyStatePodsInNamespace: #EmptyState & {
	title:       "No pods in this namespace"
	message:     "Deployments may not have scheduled pods here yet, or all pods have been removed."
	actionLabel: "Switch namespace"
	actionType:  "reload"
}

// EmptyStateClusters is shown when no cluster contexts are configured.
EmptyStateClusters: #EmptyState & {
	title:       "No clusters configured"
	message:     "Import a kubeconfig file to connect to a Kubernetes cluster."
	actionLabel: "Add cluster"
	actionType:  "configure"
}

// EmptyStateDeployments is shown when the deployment list is empty.
EmptyStateDeployments: #EmptyState & {
	title:       "No deployments in this namespace"
	message:     "No Deployment resources exist in the selected namespace."
}

// EmptyStateSearchResults is shown when command palette search returns zero results.
EmptyStateSearchResults: #EmptyState & {
	title:       "No results"
	message:     "Try a different search term or check spelling."
}

// EmptyStateToastHistory is shown when Settings → Activity Log has no entries.
EmptyStateToastHistory: #EmptyState & {
	title:       "No activity yet"
	message:     "Notification history will appear here after your first operation."
}

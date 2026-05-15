// DDD role: ValueObject
// ADR: ADR-0034 — State-driven realtime UI architecture
//
// Defines #ObservableStateContract, a conceptual value object that
// documents the binding contract between domain actor state and
// @Observable SwiftUI view models.
//
// This schema is conceptual: it cannot fully express runtime properties
// of Swift's Observation framework in CUE. It serves as a machine-readable
// specification that the architecture review tooling can validate against
// view model declarations.
//
// Swift mapping:
//
//   @MainActor
//   @Observable
//   final class SomeViewModel {
//       // stateId: "resource_list"
//       // updateSource: "actor_streamed_event"
//       // consumerScope: "DetailView"
//       var items: AsyncResource<[ItemReadModel]> = .idle
//
//       // @ObservationIgnored — not tracked by Observation framework
//       @ObservationIgnored
//       private var watchTask: Task<Void, Never>?
//   }

package app_shell

import "strings"

// #ObservableStateContract documents the contract for a single
// @Observable property in a view model. One contract per meaningful
// tracked property.
#ObservableStateContract: {
	// stateId is a kebab-case slug uniquely identifying this state property
	// within its view model.
	// Examples: "active_context", "resource_list", "editor_session",
	//           "pod_detail", "toast_stack", "namespace_list"
	stateId: string & =~"^[a-z][a-z0-9]*(_[a-z][a-z0-9]*)*$" & strings.MinRunes(2)

	// updateSource describes what produces changes to this state.
	//   actor_streamed_event  — an AsyncThrowingStream from a domain actor
	//                           (e.g. watch stream, LLM reply stream)
	//   async_resource_loaded — a one-shot async call wrapped in AsyncResource
	//   user_action           — direct mutation in response to operator input
	//                           (e.g. selecting a namespace, toggling a filter)
	updateSource: "actor_streamed_event" | "async_resource_loaded" | "user_action"

	// consumerScope describes which part of the view hierarchy reads this state.
	//   MainActor          — shared across the entire application via @Environment
	//   DetailView         — consumed only within a specific detail or list view
	//   GlobalEnvironment  — injected at app root and available to all views
	consumerScope: "MainActor" | "DetailView" | "GlobalEnvironment"

	// reactToCancellation indicates whether this state transitions to .idle
	// (for AsyncResource) or an equivalent neutral state when the parent
	// Task is cancelled. Must be true for all actor_streamed_event and
	// async_resource_loaded sources.
	reactToCancellation: bool
	reactToCancellation: *true | _

	// observationIgnored documents whether this property is annotated
	// @ObservationIgnored — meaning it does NOT trigger view re-renders.
	// Should be true for internal implementation details (e.g. watchTask).
	observationIgnored: bool
	observationIgnored: *false | _
}

// -----------------------------------------------------------------------
// Canonical observable state contracts for the app_shell bounded context
// -----------------------------------------------------------------------

// ClusterListState is the primary resource list for the sidebar's cluster
// and context listing.
ClusterListState: #ObservableStateContract & {
	stateId:             "cluster_list"
	updateSource:        "actor_streamed_event"
	consumerScope:       "GlobalEnvironment"
	reactToCancellation: true
}

// ActiveContextState tracks the operator's currently active Kubernetes context.
ActiveContextState: #ObservableStateContract & {
	stateId:             "active_context"
	updateSource:        "user_action"
	consumerScope:       "GlobalEnvironment"
	reactToCancellation: false
}

// ResourceListState is the content-list view model property for the
// currently selected resource kind in the active namespace.
ResourceListState: #ObservableStateContract & {
	stateId:             "resource_list"
	updateSource:        "actor_streamed_event"
	consumerScope:       "DetailView"
	reactToCancellation: true
}

// ResourceDetailState is the detail-panel view model property for the
// selected resource.
ResourceDetailState: #ObservableStateContract & {
	stateId:             "resource_detail"
	updateSource:        "actor_streamed_event"
	consumerScope:       "DetailView"
	reactToCancellation: true
}

// ToastStackState is the global toast overlay state shared application-wide.
ToastStackState: #ObservableStateContract & {
	stateId:             "toast_stack"
	updateSource:        "user_action"
	consumerScope:       "GlobalEnvironment"
	reactToCancellation: false
}

// EditorSessionState tracks the active editor session state per ADR-0030.
EditorSessionState: #ObservableStateContract & {
	stateId:             "editor_session"
	updateSource:        "user_action"
	consumerScope:       "DetailView"
	reactToCancellation: true
}

// -----------------------------------------------------------------------
// Architecture invariants (documented as comments; enforced in code review)
// -----------------------------------------------------------------------
//
// 1. No view may access a domain service directly. Views read only
//    @Observable view model properties.
//
// 2. No domain service or port may import SwiftUI. The boundary is strict.
//
// 3. All @Observable view model classes must be @MainActor-isolated.
//
// 4. Properties that are implementation details (e.g. Task references,
//    continuation references) must be @ObservationIgnored.
//
// 5. Shared state (e.g. ToastStack, ActiveContext) is propagated via
//    @Environment. It is NOT passed as explicit initializer arguments
//    through multiple view layers.
//
// 6. No Combine publisher, PassthroughSubject, or AnyCancellable may
//    appear in new view model files. Combine is permitted only in
//    infrastructure adapter code that bridges SwiftNIO callbacks.
//
// 7. State mutations that arrive from background actors (e.g. domain
//    actor emitting stream events) MUST be dispatched to @MainActor
//    before mutating @Observable properties. The `for try await` loop
//    inside a `Task { @MainActor in ... }` satisfies this constraint.

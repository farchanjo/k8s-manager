# ADR-0031 — Loading states and async resource UX

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — ux, loading, async, skeleton, shimmer, async-resource, accessibility

## Context and problem statement

K8sManager's UI is driven exclusively by Kubernetes API and local SQLite reads, every one of which
may take between a few milliseconds and several seconds depending on cluster latency, namespace
size, and kubeconfig health. Without a disciplined system for representing in-flight asynchronous
operations in the UI, the application will exhibit one or more of the following failure modes:

- **Flash of content** — data appears instantaneously with no transition, causing a jarring visual
  pop.
- **Blocking UI** — the operator cannot interact with other panels while a slow cluster responds.
- **Silent failure** — an error condition is not surfaced; the operator does not know whether to
  wait or retry.
- **Phantom spinner** — a spinner appears for a 20 ms SQLite read, causing unnecessary visual noise.
- **Unclear empty state** — an empty list is shown with no explanation of why it is empty and no
  call to action.

These failure modes erode trust. In a cluster-management tool where the operator needs confidence
that the state they see is accurate and current, every ambiguous loading moment reduces that
confidence.

This ADR defines the `#AsyncResource<T>` sum type and the four presentation modes (`skeleton`,
`shimmer`, `spinner`, `progressBar`) that together cover the full surface of async UX in the
application.

## Decision drivers

- **Operator trust** — the UI must make the current loading/loaded/error status unambiguous at every
  moment.
- **No UI blocking** — all async work runs in `Task`s on `@MainActor`; no operation may stall the
  render loop.
- **Consistent language** — all views that surface async data use the same vocabulary so operator
  mental models are stable across panels.
- **Accessibility** — loading states must be announced by VoiceOver and respect Reduce Motion.
- **200 ms throttle** — rapid completions (<200 ms) must not cause a flash of skeleton/shimmer. The
  throttle prevents idle → loading transitions for operations that resolve quickly.
- **Swift 6 compile-time safety** — the sum type must be defined as a Swift `enum` with associated
  values; pattern matching at every call site must be exhaustive.

## Decision outcome

### `#AsyncResource<T>` — the canonical sum type

Every async operation that affects UI state is represented as an `#AsyncResource<T>` value. The type
is defined in Swift as:

```swift
// DDD role: ValueObject
// CUE schema: contexts/app_shell/schemas/loading_state.cue #AsyncResource
enum AsyncResource<T: Sendable>: Sendable {
    case idle
    case loading(startedAt: Date, progress: Double?)
    case success(value: T, loadedAt: Date)
    case failure(error: Error, occurredAt: Date, retryable: Bool)
}
```

State is owned by a `@MainActor`-bound `@Observable` view model. The view model consumes an
`AsyncSequence` emitted by the domain layer and projects each element into an `AsyncResource`
update. The view body switches exhaustively over the current state.

### Lifecycle

```mermaid
stateDiagram-v2
    [*] --> idle : initial state
    idle --> loading : operation initiated
    loading --> loading : progress update received
    loading --> success : value received
    loading --> failure : error thrown or timeout
    success --> loading : operator refresh / watch event invalidates
    failure --> loading : operator presses Retry
    failure --> idle : operator dismisses error (non-retryable)
    success --> idle : resource navigated away (cleanup)
    loading --> idle : operator cancels

    note right of loading
        200 ms throttle:
        transition suppressed
        until 200 ms elapsed
        to avoid flash
    end note

    note right of success
        If T is empty collection:
        EmptyState rendered
        instead of content
    end note
```

### Presentation mode selection

**`loading`, estimated duration >100 ms, structural layout known** — `skeleton`.

**`loading`, estimated duration >100 ms, layout unknown or content-heavy** — `shimmer`.

**`loading`, estimated duration <500 ms (quick ops)** — `spinner` (secondary `ProgressView`).

**`loading`, known total unit count (file transfer, batch apply)** — `progressBar`.

**`success`, result collection is empty** — `EmptyState` view.

**`failure`** — `ErrorState` view with Retry and detail expand.

The 200 ms throttle applies uniformly to `skeleton`, `shimmer`, and `spinner`. If the operation
completes before the throttle fires, the view never transitions out of `idle` — there is no visible
flash.

The throttle is implemented as a `Task.sleep(for: .milliseconds(200))` guard inside the view model's
`loadResource()` method. If the underlying `async` operation resolves before the sleep expires, the
sleep task is cancelled and state stays `idle`.

### Skeleton loaders

Skeleton loaders are used for views that load data expected to take

> 100 ms and whose structural layout is known ahead of the data. Surfaces:

- **Sidebar** — cluster and context list. Skeleton shows 4 placeholder rows of varying label width
  at sidebar load.
- **Content list** — resource list (pods, deployments, services, etc.). Skeleton shows 8 placeholder
  rows matching the list row height.
- **Detail panel** — resource detail header. Skeleton shows placeholder for kind chip, name,
  namespace badge, and status chip.
- **Dashboard** — each widget card renders a skeleton card matching its final height.
- **Command palette search** — suggestion rows show skeleton while the search index warms on first
  open.

Skeleton implementation uses SwiftUI's `.redacted(reason: .placeholder)` on a template view that
mirrors the final layout. No real data is passed to the redacted view.

### Shimmer effect

Shimmer overlays a diagonal gradient animation over the `.redacted` placeholder. It is implemented
as a custom `ViewModifier`:

```swift
// Usage: anyView.shimmering()
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: phase - 0.3),
                        .init(color: .white.opacity(0.4), location: phase),
                        .init(color: .clear, location: phase + 0.3),
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.4).repeatForever(autoreverses: false)
                ) { phase = 1.3 }
            }
    }
}
```

When `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` or the `reduceMotion` theme knob is
true, the animation is replaced with a static low-opacity overlay — no repeating gradient motion.

### Spinner (secondary `ProgressView`)

A centered `ProgressView()` (indeterminate) is shown only for operations expected to complete in
<500 ms: search index queries, kubeconfig parse, namespace switch. The spinner uses
`.controlSize(.regular)` and is wrapped in a `VStack` with a caption label for accessibility.

The spinner is never used on initial data load for the primary panels (sidebar, content list,
detail). Those panels always use skeleton loaders because the first-load duration is uncontrolled.

### Empty states

When `AsyncResource` reaches `success(value:)` but the value is an empty collection, the view
renders an `EmptyState` component.

`EmptyState` structure:

- **Icon** — SF Symbol appropriate to the resource kind.
- **Title** — concise, e.g. "No pods in this namespace".
- **Message** — context, e.g. "Deployments may not have scheduled pods here yet, or all pods have
  been removed."
- **Action button** (optional) — labelled for the available action: "Create pod", "Switch
  namespace", "Reload", or "Configure cluster".

`#EmptyState` value objects are defined in `loading_state.cue` and authored per resource kind and
context. They are never generated dynamically at the view layer.

### Error states

When `AsyncResource` reaches `failure(error:)`, the view renders an `ErrorState` component.

`ErrorState` structure:

- **Icon** — `exclamationmark.triangle.fill`, status error color token.
- **Title** — "Failed to load [resource kind]".
- **Detail** (collapsed by default, expandable) — the error's `localizedDescription`. Hidden behind
  "Show details" disclosure to avoid alarming casual operators.
- **Retry button** — visible when `retryable == true`. Pressing Retry calls the domain operation
  again, transitioning back to `loading`.
- **Dismiss button** — visible when `retryable == false`. Pressing Dismiss transitions to `idle`.

### Operations never block the UI

All async domain operations are initiated via `Task { @MainActor in … }` from the view model's
`onAppear` or in response to user actions. The view model is `@Observable` and owned by the view's
`@State`. State mutations happen on `@MainActor` and trigger automatic SwiftUI re-renders.

No `DispatchSemaphore`, `wait()`, or synchronous URL loading is used. The concurrency conventions
from ADR-0011 apply without exception.

### Watch streams and async sequences

For resources backed by Kubernetes watch streams (pod list, deployment list, events), the view model
subscribes to the domain layer's `AsyncThrowingStream` and updates the `AsyncResource` on each
received event. The `AsyncResource` begins in `loading`, transitions to `success(value:)` on the
first batch, and subsequently receives incremental updates that mutate only the `value` field — the
resource does not cycle back through `loading` for watch-driven updates unless the stream is
explicitly reconnected.

### 200 ms transition throttle

To prevent visible flashes for operations that resolve in less than 200 ms (common for cached SQLite
reads and warm in-memory state), the view model delays the `idle → loading` UI transition by 200 ms.

Implementation pattern:

```swift
@Observable
final class ResourceListViewModel {
    var clusters: AsyncResource<[ClusterReadModel]> = .idle

    func loadClusters() async {
        let loadTask = Task {
            return try await clusterPort.fetchAll()
        }
        // 200 ms throttle: only transition to loading if op is still running
        try? await Task.sleep(for: .milliseconds(200))
        if !loadTask.isCancelled {
            clusters = .loading(startedAt: .now, progress: nil)
        }
        do {
            let result = try await loadTask.value
            clusters = .success(value: result, loadedAt: .now)
        } catch {
            clusters = .failure(error: error, occurredAt: .now, retryable: true)
        }
    }
}
```

### Accessibility

- `skeleton` and `shimmer` states post `accessibilityLabel("Loading")` on their container.
- `ErrorState` posts `accessibilityLabel("Error: \(title)")` and announces via
  `UIAccessibility.post(notification: .announcement, ...)` when the state first transitions to
  `failure`.
- `EmptyState` posts an appropriate `accessibilityLabel` describing the absence of content.
- Reduce Motion: all shimmer animations replaced with static overlay; all skeleton pulse animations
  suppressed; spinner remains (it is not animated in the motion-sensitive sense).

### Confirmation

- A UI test suite asserts that the sidebar transitions from `idle` to `loading` (skeleton visible)
  and then to `success` on first cold start.
- A unit test verifies that the 200 ms throttle suppresses the skeleton for a 50 ms mock operation.
- A unit test verifies `failure → loading` transition when Retry is pressed.
- A VoiceOver test asserts that empty states and error states are announced with appropriate labels.

## Considered options

### Option A — No formal pattern (ad-hoc `isLoading: Bool + error: Error?`)

Every view model owns its own `isLoading: Bool`, `error: Error?`, and `data: T?` properties.

- **Pros** — simple to add one field at a time; no upfront design.
- **Cons** — inconsistent across 30+ views; impossible to enforce 200 ms throttle uniformly;
  loading/error states are easily forgotten; empty states must be handled separately in each view;
  no single exhaustive switch forces coverage of all states. Rejected.

### Option B — `Result<T, Error>` with separate `isLoading` flag

Represent the loaded/error cases as `Result<T, Error>` and track `isLoading` separately.

- **Pros** — `Result` is a standard Swift type; familiar to Swift developers; avoids a bespoke enum.
- **Cons** — still requires a separate `isLoading` flag, creating an invalid combined state
  (`isLoading == true` while `result == .success` is possible); `idle` state is not representable
  cleanly; `progress` field for `loading` has no natural home; forces two-variable exhaustive
  matching. Rejected in favour of the richer sum type.

### Option C — `#AsyncResource<T>` sum type (chosen)

A single `enum AsyncResource<T>` with four cases — `idle`, `loading`, `success`, `failure` —
captures all states without invalid combinations. Swift's exhaustive `switch` enforces that every
call site handles all cases. Associated values carry typed metadata (progress, loadedAt, retryable)
at the point they are relevant.

- **Pros** — no invalid state combinations; exhaustive pattern matching at compile time; uniform 200
  ms throttle implementation; single vocabulary across all 30+ views; maps naturally to CUE schema
  for spec validation; easily extended with a `refreshing(previous: T)` case in future milestones.
- **Cons** — requires a new bespoke type; developers must learn the four-case vocabulary. Accepted —
  the vocabulary is small and the compile-time guarantees outweigh the learning curve.

## More information

- ADR-0011 — Swift concurrency conventions; `@MainActor` ownership, `Task` lifecycle,
  `AsyncSequence` consumption.
- ADR-0034 — State-driven realtime UI architecture; Observation framework adoption; `AsyncResource`
  is a primary state type in `@Observable` view models.
- ADR-0030 — Integrated editor; `#EditorState` is a parallel sum type for editor-specific async
  states.
- `contexts/app_shell/schemas/loading_state.cue` — CUE schema for `#AsyncResource`,
  `#LoadingPresentation`, `#EmptyState`.
- `contexts/app_shell/features/loading-states.feature` — BDD coverage.

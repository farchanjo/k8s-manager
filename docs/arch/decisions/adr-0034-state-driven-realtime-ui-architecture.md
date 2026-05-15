# ADR-0034 — State-driven realtime UI architecture

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — architecture, ui, state-management, observation, async-sequence, realtime, swiftui

## Context and problem statement

K8sManager must present live Kubernetes cluster state to the operator with sub-second latency. Pod
status changes, deployment rollout progress, node pressure, and events in the default namespace must
appear in the UI as they happen — not on the next manual refresh.

ADR-0011 establishes Swift Concurrency as the execution model and requires streams over polling. It
does not prescribe _how_ domain state flows from a Kubernetes watch stream into a SwiftUI view, and
it does not commit to a specific reactivity framework for the UI layer.

Three candidate models exist in the Swift ecosystem for binding domain state to SwiftUI:

1. **Combine + `ObservableObject`** — Apple's 2019 reactive framework, deeply integrated into early
   SwiftUI releases.
2. **Swift 6 Observation framework (`@Observable`)** — Apple's 2023 macro-based replacement for
   `ObservableObject`, recommended for new Swift 6 projects.
3. **Third-party unidirectional architecture (TCA / Pointfree Composable Architecture)** —
   opinionated reducer-based state management with a strong test story.

Without an explicit architectural decision, the codebase will drift into a mixture of all three
patterns, creating inconsistency, inflated compile times, and confusing ownership semantics.

This ADR commits to the Observation framework as the exclusive reactivity mechanism for SwiftUI
views, defines the data flow contract from Kubernetes watch streams through domain actors to
`@Observable` view models, and prohibits polling in all layers.

## Decision drivers

- **Apple's recommended path for Swift 6** — `@Observable` integrates with Swift's `@MainActor`
  isolation and `Sendable` checks; Combine's `ObservableObject` requires `@Published` which
  pre-dates strict concurrency and requires workarounds for `Sendable` conformance.
- **Granular reactivity** — `withObservationTracking` re-renders only the views that read the
  changed property; `@Published` on an `ObservableObject` re-renders the full view hierarchy that
  holds a reference to the object.
- **Single mental model** — combining Combine and Observation in the same codebase creates two
  parallel vocabularies (`sink`, `assign`, `AnyCancellable` vs. `@Observable`,
  `withObservationTracking`, `@Bindable`). Swift 6 projects should not start with Combine.
- **No polling** — watch streams emit events as they arrive; the UI subscribes once and stays live
  without periodic refresh.
- **Cancellation** — `AsyncSequence` cancellation integrates with Swift structured concurrency;
  `Task.cancel()` reaches every operator in the chain without requiring `AnyCancellable` storage.
- **Testability** — `@Observable` models are plain `class`es; injecting mock `AsyncStream` sources
  requires no Combine scheduler gymnastics.

## Pros and cons of the options

### Option A — Combine + `ObservableObject`

- Good, because Combine is Apple-supported with extensive community documentation and has been
  battle-tested in production SwiftUI apps since 2019.
- Bad, because `@Published` properties wrapped in `Publisher` require `receive(on:)` and `sink`
  with `AnyCancellable` storage when accessed from `@MainActor` async contexts; both pre-date Swift
  strict concurrency and produce `Sendable` warnings for `ObservableObject` types shared across
  actors.
- Bad, because Apple's own SwiftUI tutorials for Swift 6 migrate away from `ObservableObject`;
  starting a new Swift 6 project with Combine creates technical debt from day one.

### Option B — `@Observable` (Observation framework, chosen)

- Good, because `@Observable` is Swift 6 native with automatic `Sendable` compliance for
  `@MainActor`-isolated classes and granular per-property change tracking that reduces unnecessary
  view re-renders.
- Good, because domain ports expose `AsyncThrowingStream` consumed via `for try await` in
  `@MainActor` tasks — no `AnyCancellable` lifecycle management is required.
- Good, because `Task.cancel()` reaches every operator in the chain without `AnyCancellable`
  storage, and `@Observable` models are plain `class`es that accept mock `AsyncStream` sources in
  tests without Combine scheduler gymnastics.
- Bad, because `@Observable` requires macOS 14+ and classes must be `final` for it to work
  correctly; both constraints are already satisfied by the project's minimum deployment target.

### Option C — TCA (The Composable Architecture)

- Good, because TCA enforces unidirectional data flow, has excellent ergonomics for complex state
  machines, and is highly testable with its `Store`/`Effect` model.
- Bad, because TCA is a heavyweight third-party dependency (pulling in `swift-composable-architecture`,
  `swift-case-paths`, `swift-dependencies`, etc.) that competes with Observation tracking through its
  own `Store` reference type.
- Bad, because for a greenfield project whose primary state model is a stream of Kubernetes events,
  TCA's action/reducer ceremony adds complexity without proportional benefit over the simpler
  `@Observable` + `AsyncSequence` model.

## Decision outcome

### Core contract

Every SwiftUI view that displays live data is a pure function of one or more `@Observable` view
model properties:

```swift
// Pattern: pure view body, no business logic
struct PodListView: View {
    @State private var viewModel = PodListViewModel()

    var body: some View {
        switch viewModel.pods {
        case .idle:
            Color.clear.onAppear { viewModel.startWatching() }
        case .loading:
            PodListSkeleton()
        case .success(let pods, _) where pods.isEmpty:
            EmptyState.pods(in: viewModel.namespace)
        case .success(let pods, _):
            PodListContent(pods: pods)
        case .failure(let error, _, let retryable):
            ErrorState(error: error, retryable: retryable) {
                viewModel.startWatching()
            }
        }
    }
}
```

The view model is a `@MainActor`-bound `@Observable` class that owns the
`AsyncResource<[PodReadModel]>` state and consumes the domain port:

```swift
@MainActor
@Observable
final class PodListViewModel {
    var pods: AsyncResource<[PodReadModel]> = .idle
    private var watchTask: Task<Void, Never>?

    private let port: PodWatchPort

    func startWatching() {
        watchTask?.cancel()
        watchTask = Task {
            pods = .loading(startedAt: .now, progress: nil)
            do {
                for try await event in port.watchPods(namespace: namespace) {
                    switch event {
                    case .snapshot(let list):
                        pods = .success(value: list, loadedAt: .now)
                    case .delta(let delta):
                        applyDelta(delta)
                    }
                }
            } catch is CancellationError {
                pods = .idle
            } catch {
                pods = .failure(error: error, occurredAt: .now, retryable: true)
            }
        }
    }
}
```

### Data flow architecture

```mermaid
graph LR
    K8s["Kubernetes API Server\nHTTP/2 watch stream"]
    NIO["SwiftNIO\nMultiThreadedEventLoopGroup"]
    CSA["ClusterSessionActor\n(per cluster — ADR-0025)"]
    Port["Domain Port\nPodWatchPort\nAsyncThrowingStream"]
    VM["@Observable ViewModel\n@MainActor"]
    AR["AsyncResource state\nidle | loading | success | failure"]
    View["SwiftUI View\nbody: pure function of state"]
    Toast["ToastStack\n(ADR-0032)"]

    K8s -->|HTTP/2 chunk| NIO
    NIO -->|event loop callback| CSA
    CSA -->|AsyncThrowingStream emission| Port
    Port -->|for try await event in| VM
    VM -->|state mutation @MainActor| AR
    AR -->|withObservationTracking| View
    VM -->|ToastEmitter.emit(...)| Toast
    Toast -->|@Observable change| View
```

### Actor ownership and layer assignments

```
Layer              Type                     Actor isolation  Responsibility
-----------------  -----------------------  ---------------  -----------------------------------------------------
Infrastructure     ClusterSessionActor      custom actor     Owns HTTP/2 channel; emits raw watch events
Domain port        PodWatchPort (protocol)  nonisolated      AsyncThrowingStream<WatchEvent> contract
Domain service     PodWatchService          nonisolated      Transforms raw events into domain PodReadModel
UI view model      PodListViewModel         @MainActor       Consumes stream; owns AsyncResource<[PodReadModel]>
UI view            PodListView              @MainActor       Pure body function of @Observable state
```

No domain service or port may reference a SwiftUI type. No view may reference a domain service
directly — only view model properties.

### `Observation` framework adoption

- All view models are final `class`es annotated `@Observable`.
- Properties that drive view re-renders are stored as plain `var`.
- Properties that are internal implementation details are annotated `@ObservationIgnored` to
  suppress change tracking.
- `withObservationTracking` is used in custom view components that need granular control over which
  property changes trigger re-renders.
- `@Bindable` is used for two-way bindings between views and view model properties (e.g., filter
  text field, selected namespace picker).
- `@Environment` propagates shared `@Observable` singletons (e.g., `ToastStack`, `ThemePreference`)
  into the view hierarchy without explicit injection at every level.

### `AsyncStream` and `AsyncThrowingStream` as domain ports

All domain ports that produce live data are defined as methods returning
`AsyncThrowingStream<Event, Error>`:

```swift
protocol PodWatchPort: Sendable {
    func watchPods(namespace: String) -> AsyncThrowingStream<PodWatchEvent, Error>
}
```

The stream is backed by an `AsyncStream.Continuation` inside `ClusterSessionActor`. The
`onTermination` handler cancels the Kubernetes watch request on the HTTP/2 channel. No Combine
subject or `PassthroughSubject` is used.

### State machines via sum types

Complex view-level states beyond the four `AsyncResource` cases use explicit sum types defined as
Swift `enum`s with associated values. The `#EditorState` sum type from ADR-0030 is the reference
pattern. New state machines in this and future ADRs follow the same form:

```swift
// Example: namespace selector state machine
enum NamespaceSwitchState: Sendable {
    case idle
    case confirming(target: String)
    case switching(from: String, to: String)
    case switched(to: String, at: Date)
    case failed(error: Error, from: String, target: String)
}
```

### No polling — enforced

- No `Timer` in any view model or domain service.
- No `Task.sleep` loops for state refresh.
- No explicit "Refresh" button in the primary resource list views. Watch streams provide live
  updates; the operator does not need to request a refresh. Manual reconnect is provided only as a
  recovery mechanism on `failure` state (Retry button in `ErrorState`).
- The `SelfMonitoringSampler` (ADR-0027) uses `ContinuousClock`-backed `Task.sleep(for:)` inside an
  actor; this is the only sanctioned polling-like pattern and is scoped to self-monitoring only.

### Multiple views consuming the same observable state

When two or more views read the same `@Observable` view model property, Swift's Observation
framework coalesces change notifications: the property is read once per property access tracking
context, not once per observing view. Both views update in the same render pass when the property
changes.

Views must not hold strong references to the same view model instance via `@State` — shared models
are propagated via `@Environment` or passed as `@Binding`/`let` from a parent view that owns the
model via `@State`.

### Cancellation lifecycle

When a view disappears (e.g., the operator switches cluster or navigates away), the view model's
`watchTask` is cancelled by calling `task.cancel()` inside `.onDisappear`. The `Task` propagates
cancellation to the underlying `AsyncThrowingStream`, which triggers the `onTermination` handler in
`ClusterSessionActor`, which sends a `DELETE` to the Kubernetes watch endpoint and closes the HTTP/2
stream.

```swift
// In view body
.onDisappear { viewModel.stopWatching() }

// In view model
func stopWatching() {
    watchTask?.cancel()
    watchTask = nil
    pods = .idle
}
```

### Refines ADR-0011

This ADR extends ADR-0011 with three additions:

1. **Observation framework** is the exclusive UI reactivity mechanism; Combine is not used for new
   SwiftUI bindings.
2. **`AsyncThrowingStream`** is the canonical domain port output type for live data streams.
3. **State machines via sum types** are the required pattern for complex view-level state beyond
   simple `AsyncResource`.

The actor ownership map in ADR-0011 is not modified; the `@MainActor` and `ClusterSessionActor`
assignments remain canonical.

### Confirmation

- The project compiles with `-strict-concurrency=complete` and zero Observation-related warnings.
- A code search for `ObservableObject`, `@Published`, `AnyCancellable`, and `PassthroughSubject`
  returns zero results in new files (existing ADR-0011-grandfathered infrastructure adapters may
  retain Combine at the boundary).
- A UI test asserts that a pod status change emitted by the mock watch stream updates the pod list
  view within 500 ms without a manual refresh trigger.
- A unit test asserts that cancelling the watch task transitions `AsyncResource` state to `.idle`
  and calls `onTermination` on the stream continuation.

## Considered options

### Option A — Combine + `ObservableObject`

Use Combine's `@Published` properties on `ObservableObject` subclasses as the reactive binding
mechanism throughout the app.

- **Pros** — Apple-supported; extensive community documentation; works well with SwiftUI for simple
  cases; battle-tested in production apps since 2019.
- **Cons** — `@Published` wraps properties in `Publisher`; accessing them from `@MainActor` async
  contexts requires `receive(on:)` and `sink` with `AnyCancellable` storage, both of which pre-date
  strict concurrency. The compiler emits `Sendable` warnings for `ObservableObject` types shared
  across actors. Apple's own SwiftUI tutorials for Swift 6 migrate away from `ObservableObject`;
  starting a new Swift 6 project with Combine creates technical debt from day one. Rejected.

### Option B — `@Observable` (Observation framework) — chosen

Use Swift 5.9+'s `@Observable` macro for all view models. Domain ports expose `AsyncThrowingStream`
consumed via `for try await` in `@MainActor` tasks.

- **Pros** — Swift 6 native; `Sendable` compliance automatic for `@MainActor`-isolated classes;
  granular per-property change tracking reduces unnecessary re-renders; no `AnyCancellable`
  lifecycle management; integrates with Swift structured concurrency without bridging; Apple's
  recommended pattern for Swift 6 SwiftUI development.
- **Cons** — requires macOS 14+, which is the project's minimum deployment target (ADR-0001 or
  equivalent). Classes must be `final` for `@Observable` to work correctly with reference counting.
  Minor learning curve on `@Bindable` vs. `@Binding` distinction. Accepted — the constraints align
  with project requirements.

### Option C — TCA (The Composable Architecture)

Adopt Pointfree's TCA library as the state management layer: reducers, `Store`, `Effect`,
`ViewStore`.

- **Pros** — highly testable; enforces unidirectional data flow; excellent ergonomics for complex
  state machines; active community.
- **Cons** — heavyweight third-party dependency; TCA's `Effect` type wraps `AsyncSequence` at a
  cost; the library's `Store` is a reference type that competes with Observation tracking; TCA 1.x
  adopted `@Observable` internally but still requires the full TCA dependency graph
  (`swift-composable-architecture`, `swift-case-paths`, `swift-dependencies`, etc.); for a
  greenfield project whose primary state model is a stream of Kubernetes events, TCA's
  action/reducer ceremony adds complexity without proportional benefit. Rejected in favour of the
  lighter Observation framework approach, which provides sufficient structure through the
  `AsyncResource` and sum-type conventions defined in ADR-0031 and ADR-0030.

## More information

- ADR-0011 — Swift concurrency conventions; this ADR refines it.
- ADR-0025 — `ClusterSessionActor` ownership; emits the raw watch events consumed by domain ports.
- ADR-0030 — Integrated editor; `#EditorState` is the reference sum type pattern extended by this
  ADR.
- ADR-0031 — `AsyncResource<T>` sum type; the primary state type in `@Observable` view models
  defined by this ADR.
- ADR-0032 — Toast notification system; `#ToastStack` is an `@Observable` aggregate.
- `contexts/app_shell/schemas/observable_state.cue` — CUE schema for `#ObservableStateContract`.
- `contexts/app_shell/features/state-driven-realtime.feature` — BDD coverage.

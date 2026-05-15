# Bounded Context — `app_shell`

## Purpose

Own the model of "how K8sManager presents itself to the operator on
macOS". This context coordinates window lifecycle, sidebar, menu
bar, settings, and the surfacing of read models from the other
bounded contexts. It contains no business invariants of its own and
declares no aggregates.

## Ubiquitous language

- **Main window** — the single primary window of the application.
  The MVP runs exactly one main window; multi-window navigation is
  out of scope.
- **Sidebar** — the left-hand panel listing pinned contexts at the
  top and the recents window beneath. Powered by
  `SidebarReadModel` from `context_navigation`.
- **Cluster health badge** — a status indicator rendered alongside
  each context in the sidebar. Powered by the
  `ClusterReadModel.lastHealth` field from `cluster_connectivity`.
- **Title bar** — the macOS-native window chrome. Displays the
  active context's display name from `ActiveContextReadModel`.
- **Settings surface** — the standard macOS Settings window
  (Command-comma). The MVP exposes only one setting: the
  KUBECONFIG override path. No telemetry or auto-update preferences
  in the MVP.

## Tactical roles

- No aggregates. The shell is a consumer.
- **`MainWindowCoordinator`** — DomainService (in this context
  loosely; it borders on infrastructure). Reacts to
  `ActiveContextChanged` and re-renders the title bar and main
  content area.
- **`SidebarPresenter`** — DomainService. Transforms
  `SidebarReadModel` into `SidebarViewState` for SwiftUI.
- **`SettingsCoordinator`** — DomainService. Surfaces the
  KUBECONFIG override and writes it back to the kubeconfig loader
  port hosted by `cluster_connectivity`.

## Dependencies

- Consumes `ActiveContextReadModel` and `SidebarReadModel` from
  `context_navigation`.
- Consumes `ClusterReadModel` and
  `KubeconfigLoadReportReadModel` from `cluster_connectivity`.
- Does not import `Yams`, `SwiftkubeClient`, or any I/O library.
  SwiftUI and AppKit are part of the macOS runtime, not
  infrastructure for the purposes of this layering.

## Read models exposed to other contexts

- None. The shell is a sink.

## Invariants

- The shell never reads kubeconfig files directly.
- The shell never invokes the Kubernetes API directly.
- The shell never holds credential material.

## Out of scope

- Resource browsing, Helm, dashboards, telemetry, auto-update
  surfaces. These will arrive in later milestones and will each
  introduce their own bounded contexts or extend `app_shell`.

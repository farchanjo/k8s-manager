# DDD role: Policy
package resource_browser.applications_view

# applications_view_policy.rego
#
# Enforces the data-source contract of `ApplicationsView` (ADR-0067, Option C).
# The Applications sidebar entry currently projects exclusively from the
# `HelmManagement` read model. ArgoCD `Application` / `ApplicationSet` and Flux
# `Kustomization` aggregation is reserved as a deferred extension gated by
# CRD discovery (ADR-0052) and by the `argocdEnabled` / `fluxEnabled` feature
# flags on `#ApplicationsViewState`.
#
# This policy denies any read query issued by `ApplicationsView` that targets
# a source other than the Helm read model unless the corresponding feature
# flag is enabled AND the CRD group is confirmed installed for the cluster.
#
# input.action — "applicationsViewQuery"
# input.source — "helmReleases" | "argocdApplications" | "argocdApplicationSets"
#                | "fluxKustomizations"
# input.state  — serialised #ApplicationsViewState:
#   state.argocdEnabled — bool (default false; not yet implemented in v1)
#   state.fluxEnabled   — bool (default false; not yet implemented in v1)
# input.discoveredCRDGroups — array of API group names discovered via ADR-0052
#                             (e.g. ["argoproj.io", "kustomize.toolkit.fluxcd.io"])

import future.keywords.if
import future.keywords.in

default allow := false

# CRD group required for each non-Helm source.
crd_group_for_source := {
    "argocdApplications":     "argoproj.io",
    "argocdApplicationSets":  "argoproj.io",
    "fluxKustomizations":     "kustomize.toolkit.fluxcd.io",
}

# Feature flag required for each non-Helm source.
feature_flag_for_source := {
    "argocdApplications":     "argocdEnabled",
    "argocdApplicationSets":  "argocdEnabled",
    "fluxKustomizations":     "fluxEnabled",
}

allow if {
    count(deny_violations) == 0
}

# ---------------------------------------------------------------------------
# Deny rules
# ---------------------------------------------------------------------------

deny_violations[msg] {
    # INVARIANT V-1: source must be a recognised enum value.
    valid_sources := {
        "helmReleases",
        "argocdApplications",
        "argocdApplicationSets",
        "fluxKustomizations",
    }
    not input.source in valid_sources
    msg := sprintf(
        "applications_view.UnknownSource: source %q is not in the recognised enum {helmReleases, argocdApplications, argocdApplicationSets, fluxKustomizations}",
        [input.source],
    )
}

deny_violations[msg] {
    # INVARIANT V-2: non-Helm sources require the corresponding feature flag to
    # be enabled on the ApplicationsViewState aggregate.
    input.source != "helmReleases"
    flag_name := feature_flag_for_source[input.source]
    not input.state[flag_name]
    msg := sprintf(
        "applications_view.FeatureFlagDisabled: source %q requires state.%v = true; flag is not enabled (v1 ships Helm-only per ADR-0067)",
        [input.source, flag_name],
    )
}

deny_violations[msg] {
    # INVARIANT V-3: non-Helm sources require the corresponding CRD group to be
    # discoverable on the active cluster (ADR-0052).
    input.source != "helmReleases"
    required_group := crd_group_for_source[input.source]
    discovered := {g | g := input.discoveredCRDGroups[_]}
    not required_group in discovered
    msg := sprintf(
        "applications_view.MissingCRDGroup: source %q requires CRD group %q to be discovered; not present in cluster",
        [input.source, required_group],
    )
}

deny_violations[msg] {
    # INVARIANT V-4: the feature-flag enum cardinality must remain bounded.
    # Adding a new source requires extending feature_flag_for_source and
    # crd_group_for_source in lockstep. This rule guards future drift.
    input.source != "helmReleases"
    not feature_flag_for_source[input.source]
    msg := sprintf(
        "applications_view.PolicyDrift: source %q has no feature_flag_for_source entry; policy must be updated alongside any new aggregation source",
        [input.source],
    )
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

all_violations := deny_violations

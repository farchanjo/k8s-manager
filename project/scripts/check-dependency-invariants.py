#!/usr/bin/env python3
"""
check-dependency-invariants.py — ADR-0020 CI guard.

Verifies two architectural invariants in the K8sManager SwiftPM graph:

  1. No domain core target has any infrastructure library in its transitive
     dependency closure. Allows only SharedKernel, swift-dependencies,
     swift-log, swift-metrics, and Foundation/stdlib in domain cores.

  2. AppShell has zero adapter target imports — it may only depend on domain
     cores and approved utility packages.

Usage:
    cd project/
    python3 scripts/check-dependency-invariants.py

Exit codes:
    0 — all invariants satisfied
    1 — one or more violations found
    2 — invocation error (wrong cwd, swift not found, JSON parse failure)
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Domain core targets — MUST NOT transitively import any infrastructure lib.
DOMAIN_CORES: list[str] = [
    "SharedKernel",
    "ClusterConnectivity",
    "ContextNavigation",
    "LLMProvider",
    "AssistantChat",
    "ClusterIntelligence",
    "LocalPersistence",
    "ResourceBrowser",
    "PortForwarding",
    "HelmManagement",
    "MetricsObservability",
    "TerminalSession",
]

# Infrastructure library names (canonical package/product identifiers as they
# appear in `swift package show-dependencies` JSON output).  Case-insensitive
# match against "identity" and "name" fields.
FORBIDDEN_INFRA_LIBS: list[str] = [
    "swiftkube-client",       # SwiftkubeClient
    "swiftclient",            # alternate identity SwiftkubeClient uses
    "GRDB",                   # GRDB.swift
    "grdb.swift",
    "Yams",
    "async-http-client",
    "soto",
    "SotoCore",
    "SotoSTS",
    "MSAL",
    "microsoft-authentication-library-for-objc",
    "AppAuth",
    "appauth-ios",
    "SwiftAnthropic",
    "OpenAI",
    "swift-sdk",              # modelcontextprotocol/swift-sdk
    "swift-crypto",
    "Crypto",
    "jwt-kit",
    "CodeEditorView",
    "code-editor-view",
]

# Adapter target names — must not appear in AppShell's transitive deps.
ADAPTER_TARGETS: list[str] = [
    "SwiftkubeClientAdapter",
    "YamsKubeconfigAdapter",
    "KeychainAdapter",
    "GRDBPersistenceAdapter",
    "AnthropicAdapter",
    "OpenAIAdapter",
    "OpenAICompatibleAdapter",
    "MCPSwiftSDKAdapter",
    "AWSExecCredentialAdapter",
    "GCPExecCredentialAdapter",
    "AzureExecCredentialAdapter",
    "OIDCExecCredentialAdapter",
    "SubprocessExecCredentialAdapter",
    "PrometheusQueryAdapter",
    "WebSocketExecAdapter",
    "WebSocketPortForwardAdapter",
    "CodeEditorAdapter",
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _normalise(name: str) -> str:
    """Lowercase + strip hyphens/underscores for fuzzy identity matching."""
    return name.lower().replace("-", "").replace("_", "").replace(".", "")


_FORBIDDEN_NORMALISED: set[str] = {_normalise(lib) for lib in FORBIDDEN_INFRA_LIBS}
_ADAPTER_NORMALISED: set[str] = {_normalise(t) for t in ADAPTER_TARGETS}


def _is_forbidden_infra(dep_name: str) -> bool:
    return _normalise(dep_name) in _FORBIDDEN_NORMALISED


def _is_adapter(dep_name: str) -> bool:
    return _normalise(dep_name) in _ADAPTER_NORMALISED


def _collect_transitive_deps(
    target_name: str,
    dep_graph: dict[str, list[str]],
    visited: set[str] | None = None,
) -> set[str]:
    """Return the full set of transitive dependency names for *target_name*."""
    if visited is None:
        visited = set()
    if target_name in visited:
        return visited
    visited.add(target_name)
    for dep in dep_graph.get(target_name, []):
        _collect_transitive_deps(dep, dep_graph, visited)
    return visited


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    # Verify we are inside the package directory.
    if not Path("Package.swift").exists():
        print(
            "ERROR: Package.swift not found. Run this script from the project/ directory.",
            file=sys.stderr,
        )
        return 2

    print("Fetching dependency graph …")
    try:
        result = subprocess.run(
            ["swift", "package", "show-dependencies", "--format", "json"],
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        print("ERROR: `swift` binary not found in PATH.", file=sys.stderr)
        return 2
    except subprocess.CalledProcessError as exc:
        print(f"ERROR: `swift package show-dependencies` failed:\n{exc.stderr}", file=sys.stderr)
        return 2

    try:
        graph_root: dict = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print(f"ERROR: Failed to parse JSON output: {exc}", file=sys.stderr)
        return 2

    # Build a simple adjacency map: target name → list of direct dep names.
    # The JSON schema from SwiftPM show-dependencies is:
    #   { "name": "...", "dependencies": [ { "name": ..., "dependencies": [...] }, ... ] }
    # We flatten the whole tree into a unique set and also build the adjacency.

    dep_graph: dict[str, list[str]] = {}
    all_package_names: set[str] = set()

    def _walk(node: dict) -> None:
        name = node.get("name", "")
        all_package_names.add(name)
        children = [child.get("name", "") for child in node.get("dependencies", [])]
        dep_graph.setdefault(name, []).extend(children)
        for child in node.get("dependencies", []):
            _walk(child)

    _walk(graph_root)

    violations: list[str] = []

    # Invariant 1 — domain cores must not transitively depend on infra libs.
    print("\nChecking domain core isolation …")
    for core in DOMAIN_CORES:
        transitive = _collect_transitive_deps(core, dep_graph)
        for dep in transitive:
            if _is_forbidden_infra(dep):
                msg = (
                    f"VIOLATION (domain-core): {core} → transitive dep on "
                    f"forbidden infrastructure library '{dep}'"
                )
                print(f"  {msg}")
                violations.append(msg)

    # Invariant 2 — AppShell must not transitively depend on any adapter.
    print("\nChecking AppShell adapter isolation …")
    app_shell_transitive = _collect_transitive_deps("AppShell", dep_graph)
    for dep in app_shell_transitive:
        if _is_adapter(dep):
            msg = (
                f"VIOLATION (appshell-adapter): AppShell → transitive dep on "
                f"adapter target '{dep}'"
            )
            print(f"  {msg}")
            violations.append(msg)

    # Summary
    print()
    if violations:
        print(f"FAILED — {len(violations)} invariant violation(s) found.")
        for v in violations:
            print(f"  • {v}")
        return 1

    print("OK — all dependency invariants satisfied.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

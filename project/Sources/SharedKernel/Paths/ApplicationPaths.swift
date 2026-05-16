// SharedKernel/Paths/ApplicationPaths.swift
// DDD role: infrastructure utility — canonical path resolver
// ADR refs: ADR-0010 (storage design), ADR-0026 (filesystem layout), ADR-0042 (instance lock, network-volume rejection)

import Foundation

// MARK: - ApplicationPaths

/// Central resolver for every well-known path used by K8sManager.
///
/// All paths are rooted at `~/Library/Application Support/K8sManager/` as
/// mandated by macOS HIG and `applicationSupportDirectory`. No call site should
/// construct these paths inline — always use this enum instead.
///
/// The storage root is created with `0700` permissions by
/// ``ensureSupportDirectoryExists()``; call this once before any file access.
///
/// ADR-0026 documents the rationale for using `applicationSupportDirectory`
/// over the XDG `~/.config` path that appeared in the early draft.
public enum ApplicationPaths: Sendable {

    // MARK: Root

    /// Absolute URL to `~/Library/Application Support/K8sManager/`.
    ///
    /// Resolved via `FileManager.default.urls(for:in:)` on every access so that
    /// tests can rely on a stable sandbox container path without additional
    /// configuration.
    public static var supportDirectory: URL {
        // force-unwrap is safe: applicationSupportDirectory always resolves on
        // macOS 14+; the fallback would be a programmer error at composition time.
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("K8sManager", isDirectory: true)
    }

    // MARK: Well-known paths

    /// Absolute URL to `storage.sqlite3` (WAL mode, GRDB — ADR-0010).
    public static var storageURL: URL {
        supportDirectory.appendingPathComponent("storage.sqlite3")
    }

    /// Absolute URL to `.instance.lock` (POSIX flock guard — ADR-0042).
    public static var instanceLockURL: URL {
        supportDirectory.appendingPathComponent(".instance.lock")
    }

    /// Absolute URL to the `clusters/` subtree (per-cluster JSON state — ADR-0025).
    public static var clusterStateRoot: URL {
        supportDirectory.appendingPathComponent("clusters", isDirectory: true)
    }

    /// Absolute URL to the `logs/` subtree (daily-rotated log files — ADR-0026).
    public static var logDirectory: URL {
        supportDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    /// Absolute URL to the workspace-state subtree — JSON files that are not
    /// scoped to any single cluster (workspace tabs, future workspace-level
    /// preferences). Backs ADR-0054 workspace-tab persistence.
    public static var workspaceStateRoot: URL {
        supportDirectory.appendingPathComponent("workspace", isDirectory: true)
    }

    /// Absolute URL to `workspace/workspace-tabs.json` (ADR-0054 — persistent
    /// Welcome tab + any future workspace-scoped tab kinds).
    public static var workspaceTabsURL: URL {
        workspaceStateRoot.appendingPathComponent("workspace-tabs.json")
    }

    /// Absolute URL to `workspace/navigation-history.json` (ADR-0065 — per-window
    /// navigation history stack).
    public static var navigationHistoryURL: URL {
        workspaceStateRoot.appendingPathComponent("navigation-history.json")
    }

    /// Absolute URL to `workspace/docked-terminal-pane.json` (ADR-0057 — bottom-docked
    /// terminal pane state: open tabs, pane height, active tab id).
    public static var dockedTerminalPaneURL: URL {
        workspaceStateRoot.appendingPathComponent("docked-terminal-pane.json")
    }

    /// Absolute URL to `workspace/docked-yaml-editor-pane.json` (ADR-0064 — inline
    /// docked YAML editor pane state: active draft, pane height).
    public static var dockedYAMLEditorPaneURL: URL {
        workspaceStateRoot.appendingPathComponent("docked-yaml-editor-pane.json")
    }

    // MARK: Bootstrap

    /// Creates `supportDirectory` with `0700` permissions if it does not already
    /// exist. Safe to call multiple times (idempotent via
    /// `withIntermediateDirectories: true`).
    ///
    /// Call this once at the start of the bootstrap sequence, before any file
    /// access that targets paths under ``supportDirectory``.
    ///
    /// - Throws: `CocoaError` if directory creation fails for a reason other than
    ///   the directory already existing.
    public static func ensureSupportDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    // MARK: Network-volume detection (ADR-0042)

    /// Returns `true` when the volume hosting `url` is a local (non-network) filesystem.
    ///
    /// Uses `URLResourceKey.volumeIsLocalKey` which honours macOS's kernel-level
    /// volume attribute without requiring `statfs(2)` directly. A `false` return
    /// means the path resides on NFS, SMB, AFP, WebDAV, or another remote volume
    /// and the app must refuse to use it for storage (ADR-0042 §Network-volume rejection).
    ///
    /// - Parameter url: Any URL whose volume should be probed. The volume is
    ///   resolved from `url.deletingLastPathComponent()` so the file itself need
    ///   not exist yet (it is safe to probe the parent directory).
    /// - Returns: `true` if the hosting volume reports itself as local.
    /// - Throws: A `CocoaError` if the resource value cannot be read (e.g. the
    ///   directory does not exist or is inaccessible).
    public static func isLocalVolume(at url: URL) throws -> Bool {
        let directory = url.deletingLastPathComponent()
        let values = try directory.resourceValues(forKeys: [.volumeIsLocalKey])
        return values.volumeIsLocal ?? true
    }
}

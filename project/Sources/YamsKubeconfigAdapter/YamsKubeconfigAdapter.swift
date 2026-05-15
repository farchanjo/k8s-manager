// YamsKubeconfigAdapter.swift — infrastructure adapter
// Implements: KubeconfigLoaderPort from ClusterConnectivity
// Library: jpsim/Yams@5.4+ (Tier A per ADR-0019)

import ClusterConnectivity
import Foundation
import SharedKernel
import Yams

// MARK: - YamsKubeconfigLoader

/// Parses kubeconfig YAML from disk into the `Kubeconfig` domain aggregate.
///
/// Thread-safe: all state is stack-local; the struct carries no mutable
/// storage. File I/O is dispatched off the calling actor.
public struct YamsKubeconfigLoader: KubeconfigLoaderPort, Sendable {
    public init() {}

    // MARK: KubeconfigLoaderPort

    public func load(from path: KubeconfigPath) async throws -> Kubeconfig {
        let resolvedPath = Self.resolveTilde(path.rawValue)

        let (content, mtime) = try await Task.detached(priority: .utility) {
            try Self.readFile(at: resolvedPath)
        }.value

        return try Self.parse(yaml: content, sourcePath: resolvedPath, mtime: mtime)
    }

    public func contexts(in config: Kubeconfig) -> [KubeconfigContext] {
        config.contexts
    }

    public func activeContext(in config: Kubeconfig) -> KubeconfigContext? {
        guard let current = config.currentContext else { return nil }
        return config.contexts.first { $0.name == current }
    }

    // MARK: - Path helpers

    private static func resolveTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + path.dropFirst()
    }

    // MARK: - File I/O (runs in detached task)

    private static func readFile(at path: String) throws -> (String, String) {
        let url = URL(fileURLWithPath: path)
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let mtime = (attrs[.modificationDate] as? Date).map(RFC3339Formatter.string) ?? ""
            return (content, mtime)
        } catch {
            throw KubeconfigLoadError.ioError(path: path, underlying: error.localizedDescription)
        }
    }

    // MARK: - YAML parsing

    private static func parse(
        yaml content: String,
        sourcePath: String,
        mtime: String
    ) throws -> Kubeconfig {
        let anyValue: Any
        do {
            guard let parsed = try Yams.load(yaml: content) else {
                throw KubeconfigLoadError.parseError(detail: "YAML resolved to nil root node")
            }
            anyValue = parsed
        } catch let loadError as KubeconfigLoadError {
            throw loadError
        } catch {
            throw KubeconfigLoadError.parseError(detail: error.localizedDescription)
        }

        guard let root = anyValue as? [String: Any] else {
            throw KubeconfigLoadError.parseError(detail: "Root YAML node is not a mapping")
        }

        let currentContext = root["current-context"] as? String

        let clusters = try parseClusters(root["clusters"])
        let users = try parseUsers(root["users"])
        let contexts = try parseContexts(root["contexts"])

        return Kubeconfig(
            sourcePath: KubeconfigPath(sourcePath),
            sourceMTimeRFC3339: mtime,
            currentContext: currentContext,
            clusters: clusters,
            users: users,
            contexts: contexts
        )
    }

    // MARK: - Cluster parsing

    private static func parseClusters(_ raw: Any?) throws -> [KubeconfigCluster] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return try list.map { try parseClusterEntry($0) }
    }

    private static func parseClusterEntry(_ entry: [String: Any]) throws -> KubeconfigCluster {
        guard let name = entry["name"] as? String else {
            throw KubeconfigLoadError.parseError(detail: "Cluster entry missing 'name' field")
        }
        let clusterMap = entry["cluster"] as? [String: Any] ?? [:]
        let server = clusterMap["server"] as? String ?? ""
        return KubeconfigCluster(
            name: name,
            server: server,
            certificateAuthorityPath: clusterMap["certificate-authority"] as? String,
            certificateAuthorityData: clusterMap["certificate-authority-data"] as? String,
            insecureSkipTLSVerify: clusterMap["insecure-skip-tls-verify"] as? Bool ?? false
        )
    }

    // MARK: - User parsing

    private static func parseUsers(_ raw: Any?) throws -> [KubeconfigUser] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return try list.map { try parseUserEntry($0) }
    }

    private static func parseUserEntry(_ entry: [String: Any]) throws -> KubeconfigUser {
        guard let name = entry["name"] as? String else {
            throw KubeconfigLoadError.parseError(detail: "User entry missing 'name' field")
        }
        let userMap = entry["user"] as? [String: Any] ?? [:]
        let execConfig = try parseExecConfig(userMap["exec"])
        return KubeconfigUser(
            name: name,
            clientCertificatePath: userMap["client-certificate"] as? String,
            clientCertificateData: userMap["client-certificate-data"] as? String,
            clientKeyPath: userMap["client-key"] as? String,
            clientKeyData: userMap["client-key-data"] as? String,
            token: userMap["token"] as? String,
            tokenFile: userMap["tokenFile"] as? String,
            exec: execConfig
        )
    }

    // MARK: - ExecConfig parsing

    private static func parseExecConfig(_ raw: Any?) throws -> KubeconfigUser.ExecConfig? {
        guard let map = raw as? [String: Any] else { return nil }
        guard let command = map["command"] as? String else {
            throw KubeconfigLoadError.parseError(detail: "exec block missing 'command' field")
        }
        let apiVersion = map["apiVersion"] as? String ?? "client.authentication.k8s.io/v1"
        let args = map["args"] as? [String] ?? []
        let envVars = parseEnvVars(map["env"])
        return KubeconfigUser.ExecConfig(
            apiVersion: apiVersion,
            command: command,
            args: args,
            env: envVars,
            installHint: map["installHint"] as? String,
            provideClusterInfo: map["provideClusterInfo"] as? Bool ?? false
        )
    }

    private static func parseEnvVars(_ raw: Any?) -> [EnvVar] {
        guard let list = raw as? [[String: String]] else { return [] }
        return list.compactMap { entry in
            guard let name = entry["name"], let value = entry["value"] else { return nil }
            return EnvVar(name: name, value: value)
        }
    }

    // MARK: - Context parsing

    private static func parseContexts(_ raw: Any?) throws -> [KubeconfigContext] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return try list.map { try parseContextEntry($0) }
    }

    private static func parseContextEntry(_ entry: [String: Any]) throws -> KubeconfigContext {
        guard let name = entry["name"] as? String else {
            throw KubeconfigLoadError.parseError(detail: "Context entry missing 'name' field")
        }
        let ctxMap = entry["context"] as? [String: Any] ?? [:]
        return KubeconfigContext(
            name: name,
            cluster: ctxMap["cluster"] as? String ?? "",
            user: ctxMap["user"] as? String ?? "",
            namespace: ctxMap["namespace"] as? String ?? "default"
        )
    }
}

// MARK: - RFC3339Formatter

private enum RFC3339Formatter {
    /// Returns an RFC 3339 string for `date`.
    ///
    /// A new formatter is created per call to avoid sharing mutable state
    /// across actor boundaries (Swift 6 strict concurrency).
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// YamsKubeconfigAdapterTests.swift — infrastructure adapter integration tests
// Coverage: minimal kubeconfig, exec-auth, base64-CA, activeContext resolution,
//           missing file I/O error.

import XCTest
import Foundation
@testable import YamsKubeconfigAdapter
import ClusterConnectivity
import SharedKernel

// MARK: - YamsKubeconfigLoaderTests

final class YamsKubeconfigLoaderTests: XCTestCase {
    private let loader = YamsKubeconfigLoader()

    // MARK: - Helpers

    private func writeTempFile(_ content: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("kubeconfig-\(UUID().uuidString).yaml")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: - Minimal kubeconfig

    func test_load_minimal_kubeconfig_roundtrips_fields() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: dev
        clusters:
          - name: dev-cluster
            cluster:
              server: https://127.0.0.1:6443
              insecure-skip-tls-verify: true
        users:
          - name: dev-user
            user:
              token: my-static-token
        contexts:
          - name: dev
            context:
              cluster: dev-cluster
              user: dev-user
              namespace: kube-system
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let cfg = try await loader.load(from: KubeconfigPath(path))

        XCTAssertEqual(cfg.sourcePath, KubeconfigPath(path))
        XCTAssertFalse(cfg.sourceMTimeRFC3339.isEmpty)
        XCTAssertEqual(cfg.currentContext, "dev")

        XCTAssertEqual(cfg.clusters.count, 1)
        let cluster = try XCTUnwrap(cfg.clusters.first)
        XCTAssertEqual(cluster.name, "dev-cluster")
        XCTAssertEqual(cluster.server, "https://127.0.0.1:6443")
        XCTAssertTrue(cluster.insecureSkipTLSVerify)
        XCTAssertNil(cluster.certificateAuthorityPath)
        XCTAssertNil(cluster.certificateAuthorityData)

        XCTAssertEqual(cfg.users.count, 1)
        let user = try XCTUnwrap(cfg.users.first)
        XCTAssertEqual(user.name, "dev-user")
        XCTAssertEqual(user.token, "my-static-token")
        XCTAssertNil(user.exec)

        XCTAssertEqual(cfg.contexts.count, 1)
        let ctx = try XCTUnwrap(cfg.contexts.first)
        XCTAssertEqual(ctx.name, "dev")
        XCTAssertEqual(ctx.cluster, "dev-cluster")
        XCTAssertEqual(ctx.user, "dev-user")
        XCTAssertEqual(ctx.namespace, "kube-system")
    }

    // MARK: - Exec-auth block

    func test_load_kubeconfig_with_exec_auth_roundtrips_execconfig() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: gke-prod
        clusters:
          - name: gke-prod
            cluster:
              server: https://34.100.0.1
        users:
          - name: gke-user
            user:
              exec:
                apiVersion: client.authentication.k8s.io/v1beta1
                command: gke-gcloud-auth-plugin
                args:
                  - --use_application_default_credentials
                env:
                  - name: CLOUDSDK_CORE_PROJECT
                    value: my-gcp-project
                installHint: Install gke-gcloud-auth-plugin.
                provideClusterInfo: true
        contexts:
          - name: gke-prod
            context:
              cluster: gke-prod
              user: gke-user
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let cfg = try await loader.load(from: KubeconfigPath(path))

        let user = try XCTUnwrap(cfg.users.first)
        let exec = try XCTUnwrap(user.exec, "exec block should be present")

        XCTAssertEqual(exec.apiVersion, "client.authentication.k8s.io/v1beta1")
        XCTAssertEqual(exec.command, "gke-gcloud-auth-plugin")
        XCTAssertEqual(exec.args, ["--use_application_default_credentials"])
        XCTAssertTrue(exec.provideClusterInfo)
        XCTAssertEqual(exec.installHint, "Install gke-gcloud-auth-plugin.")

        XCTAssertEqual(exec.env.count, 1)
        let envVar = try XCTUnwrap(exec.env.first)
        XCTAssertEqual(envVar.name, "CLOUDSDK_CORE_PROJECT")
        XCTAssertEqual(envVar.value, "my-gcp-project")
    }

    // MARK: - Base64 CA data

    func test_load_kubeconfig_with_base64_ca_data_is_preserved() async throws {
        // A synthetic base64-encoded string (not a real cert — just checking field passthrough).
        let fakeB64CA = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: kind-local
        clusters:
          - name: kind-local
            cluster:
              server: https://127.0.0.1:6443
              certificate-authority-data: \(fakeB64CA)
        users:
          - name: kind-admin
            user:
              client-certificate-data: \(fakeB64CA)
              client-key-data: \(fakeB64CA)
        contexts:
          - name: kind-local
            context:
              cluster: kind-local
              user: kind-admin
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let cfg = try await loader.load(from: KubeconfigPath(path))

        let cluster = try XCTUnwrap(cfg.clusters.first)
        XCTAssertEqual(cluster.certificateAuthorityData, fakeB64CA)
        XCTAssertNil(cluster.certificateAuthorityPath)

        let user = try XCTUnwrap(cfg.users.first)
        XCTAssertEqual(user.clientCertificateData, fakeB64CA)
        XCTAssertEqual(user.clientKeyData, fakeB64CA)
    }

    // MARK: - contexts(in:)

    func test_contexts_returns_all_entries() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        clusters: []
        users: []
        contexts:
          - name: ctx-a
            context:
              cluster: a
              user: u
          - name: ctx-b
            context:
              cluster: b
              user: u
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let cfg = try await loader.load(from: KubeconfigPath(path))
        let ctxs = loader.contexts(in: cfg)
        XCTAssertEqual(ctxs.map(\.name), ["ctx-a", "ctx-b"])
    }

    // MARK: - activeContext

    func test_activeContext_returns_matching_context() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: staging
        clusters: []
        users: []
        contexts:
          - name: prod
            context:
              cluster: prod
              user: admin
          - name: staging
            context:
              cluster: stg
              user: dev
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let cfg = try await loader.load(from: KubeconfigPath(path))
        let active = loader.activeContext(in: cfg)
        XCTAssertEqual(active?.name, "staging")
        XCTAssertEqual(active?.cluster, "stg")
    }

    func test_activeContext_returns_nil_when_currentContext_absent() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        clusters: []
        users: []
        contexts:
          - name: prod
            context:
              cluster: prod
              user: admin
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let cfg = try await loader.load(from: KubeconfigPath(path))
        let active = loader.activeContext(in: cfg)
        XCTAssertNil(active)
    }

    // MARK: - I/O error

    func test_load_throws_ioError_when_path_does_not_exist() async {
        let path = KubeconfigPath("/tmp/nonexistent-kubeconfig-\(UUID().uuidString).yaml")
        do {
            _ = try await loader.load(from: path)
            XCTFail("Expected KubeconfigLoadError.ioError to be thrown")
        } catch KubeconfigLoadError.ioError(let errPath, _) {
            XCTAssertTrue(errPath.contains("nonexistent"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Namespace defaults to "default"

    func test_context_namespace_defaults_to_default_when_absent() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        clusters: []
        users: []
        contexts:
          - name: no-ns
            context:
              cluster: c
              user: u
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let cfg = try await loader.load(from: KubeconfigPath(path))
        let ctx = try XCTUnwrap(cfg.contexts.first)
        XCTAssertEqual(ctx.namespace, "default")
    }
}

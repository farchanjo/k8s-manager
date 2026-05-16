// YamsKubeconfigLoaderTests.swift — unit tests for YamsKubeconfigLoader
// Coverage: parse(yaml:) in-memory path (ADR-0056 clipboard import), exec block,
//           inline base64-CA, symlink-resolved sourcePath, namespace default,
//           I/O error mapping, context helpers.

import XCTest
import Foundation
@testable import YamsKubeconfigAdapter
import ClusterConnectivity
import SharedKernel

// MARK: - YamsKubeconfigLoaderTests

final class YamsKubeconfigLoaderExtendedTests: XCTestCase {

    private let loader = YamsKubeconfigLoader()

    // MARK: - Helpers

    private func writeTempFile(_ content: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("kubeconfig-\(UUID().uuidString).yaml")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    // MARK: - parse(yaml:) — in-memory clipboard import (ADR-0056)

    func test_parseYAML_minimalKubeconfig_roundtripsFields() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: local
        clusters:
          - name: local-cluster
            cluster:
              server: https://127.0.0.1:6443
        users:
          - name: local-user
            user:
              token: s3cr3t
        contexts:
          - name: local
            context:
              cluster: local-cluster
              user: local-user
              namespace: default
        """

        let config = try await loader.parse(yaml: yaml)

        XCTAssertEqual(config.sourcePath, KubeconfigPath("<clipboard>"))
        XCTAssertTrue(config.sourceMTimeRFC3339.isEmpty)
        XCTAssertEqual(config.currentContext, "local")
        XCTAssertEqual(config.clusters.count, 1)
        XCTAssertEqual(config.clusters.first?.server, "https://127.0.0.1:6443")
        XCTAssertEqual(config.users.count, 1)
        XCTAssertEqual(config.users.first?.token, "s3cr3t")
        XCTAssertEqual(config.contexts.count, 1)
    }

    func test_parseYAML_emptyYAML_throwsParseError() async {
        do {
            _ = try await loader.parse(yaml: "")
            XCTFail("Expected KubeconfigLoadError.parseError")
        } catch KubeconfigLoadError.parseError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_parseYAML_invalidYAML_throwsParseError() async {
        let badYAML = "{ invalid: yaml: : :"
        do {
            _ = try await loader.parse(yaml: badYAML)
            XCTFail("Expected KubeconfigLoadError.parseError")
        } catch KubeconfigLoadError.parseError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_parseYAML_scalarRoot_throwsParseError() async {
        do {
            _ = try await loader.parse(yaml: "just-a-scalar")
            XCTFail("Expected KubeconfigLoadError.parseError")
        } catch KubeconfigLoadError.parseError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - load(from:) — disk path + mtime

    func test_load_minimalKubeconfig_populatesMTime() async throws {
        let yaml = minimalKubeconfigYAML(context: "dev")
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try await loader.load(from: KubeconfigPath(path))

        XCTAssertEqual(config.sourcePath, KubeconfigPath(path))
        XCTAssertFalse(config.sourceMTimeRFC3339.isEmpty, "mtime should be set on disk load")
        XCTAssertEqual(config.currentContext, "dev")
    }

    func test_load_execAuthBlock_roundtripsExecConfig() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: eks-prod
        clusters:
          - name: eks-prod
            cluster:
              server: https://ABCDEF.gr7.us-east-1.eks.amazonaws.com
        users:
          - name: eks-admin
            user:
              exec:
                apiVersion: client.authentication.k8s.io/v1beta1
                command: aws
                args:
                  - eks
                  - get-token
                  - --cluster-name
                  - my-cluster
                env:
                  - name: AWS_PROFILE
                    value: production
                installHint: Install AWS CLI.
                provideClusterInfo: true
        contexts:
          - name: eks-prod
            context:
              cluster: eks-prod
              user: eks-admin
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try await loader.load(from: KubeconfigPath(path))
        let user = try XCTUnwrap(config.users.first)
        let exec = try XCTUnwrap(user.exec, "exec block should be parsed")

        XCTAssertEqual(exec.command, "aws")
        XCTAssertEqual(exec.apiVersion, "client.authentication.k8s.io/v1beta1")
        XCTAssertEqual(exec.args, ["eks", "get-token", "--cluster-name", "my-cluster"])
        XCTAssertTrue(exec.provideClusterInfo)
        XCTAssertEqual(exec.installHint, "Install AWS CLI.")

        let envVar = try XCTUnwrap(exec.env.first)
        XCTAssertEqual(envVar.name, "AWS_PROFILE")
        XCTAssertEqual(envVar.value, "production")
    }

    func test_load_inlineBase64CA_preservedVerbatim() async throws {
        let fakeB64 = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: kind-test
        clusters:
          - name: kind-test
            cluster:
              server: https://127.0.0.1:6443
              certificate-authority-data: \(fakeB64)
        users:
          - name: kind-admin
            user:
              client-certificate-data: \(fakeB64)
              client-key-data: \(fakeB64)
        contexts:
          - name: kind-test
            context:
              cluster: kind-test
              user: kind-admin
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try await loader.load(from: KubeconfigPath(path))

        let cluster = try XCTUnwrap(config.clusters.first)
        XCTAssertEqual(cluster.certificateAuthorityData, fakeB64)
        XCTAssertNil(cluster.certificateAuthorityPath)

        let user = try XCTUnwrap(config.users.first)
        XCTAssertEqual(user.clientCertificateData, fakeB64)
        XCTAssertEqual(user.clientKeyData, fakeB64)
    }

    func test_load_caFileRef_preservedAsPath() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: local
        clusters:
          - name: local
            cluster:
              server: https://127.0.0.1:6443
              certificate-authority: /etc/ssl/ca.pem
        users:
          - name: local-user
            user:
              client-certificate: /etc/ssl/client.crt
              client-key: /etc/ssl/client.key
        contexts:
          - name: local
            context:
              cluster: local
              user: local-user
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try await loader.load(from: KubeconfigPath(path))

        let cluster = try XCTUnwrap(config.clusters.first)
        XCTAssertEqual(cluster.certificateAuthorityPath, "/etc/ssl/ca.pem")
        XCTAssertNil(cluster.certificateAuthorityData)

        let user = try XCTUnwrap(config.users.first)
        XCTAssertEqual(user.clientCertificatePath, "/etc/ssl/client.crt")
        XCTAssertEqual(user.clientKeyPath, "/etc/ssl/client.key")
    }

    // MARK: - Namespace defaulting

    func test_context_namespaceDefaultsToDefault_whenAbsent() async throws {
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

        let config = try await loader.load(from: KubeconfigPath(path))
        let ctx = try XCTUnwrap(config.contexts.first)
        XCTAssertEqual(ctx.namespace, "default")
    }

    // MARK: - Context helpers

    func test_contexts_returnsAllEntries() async throws {
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

        let config = try await loader.load(from: KubeconfigPath(path))
        XCTAssertEqual(loader.contexts(in: config).map(\.name), ["ctx-a", "ctx-b"])
    }

    func test_activeContext_matchesCurrentContext() async throws {
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

        let config = try await loader.load(from: KubeconfigPath(path))
        let active = loader.activeContext(in: config)
        XCTAssertEqual(active?.name, "staging")
        XCTAssertEqual(active?.cluster, "stg")
    }

    func test_activeContext_nilWhenCurrentContextAbsent() async throws {
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

        let config = try await loader.load(from: KubeconfigPath(path))
        XCTAssertNil(loader.activeContext(in: config))
    }

    // MARK: - I/O error

    func test_load_throwsIOError_whenPathDoesNotExist() async {
        let missingPath = KubeconfigPath("/tmp/missing-\(UUID().uuidString).yaml")
        do {
            _ = try await loader.load(from: missingPath)
            XCTFail("Expected KubeconfigLoadError.ioError")
        } catch KubeconfigLoadError.ioError(let errPath, _) {
            XCTAssertTrue(errPath.contains("missing"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Multi-cluster kubeconfig

    func test_load_multiCluster_parsesAllClusters() async throws {
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: ctx-a
        clusters:
          - name: cluster-a
            cluster:
              server: https://a.example.com
          - name: cluster-b
            cluster:
              server: https://b.example.com
              insecure-skip-tls-verify: true
        users:
          - name: user-a
            user:
              token: tok-a
        contexts:
          - name: ctx-a
            context:
              cluster: cluster-a
              user: user-a
        """
        let path = try writeTempFile(yaml)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let config = try await loader.load(from: KubeconfigPath(path))
        XCTAssertEqual(config.clusters.count, 2)

        let clusterB = try XCTUnwrap(config.clusters.first { $0.name == "cluster-b" })
        XCTAssertTrue(clusterB.insecureSkipTLSVerify)
        XCTAssertEqual(clusterB.server, "https://b.example.com")
    }

    // MARK: - Private fixture

    private func minimalKubeconfigYAML(context: String) -> String {
        """
        apiVersion: v1
        kind: Config
        current-context: \(context)
        clusters:
          - name: \(context)-cluster
            cluster:
              server: https://127.0.0.1:6443
        users:
          - name: \(context)-user
            user:
              token: tok-\(context)
        contexts:
          - name: \(context)
            context:
              cluster: \(context)-cluster
              user: \(context)-user
        """
    }
}

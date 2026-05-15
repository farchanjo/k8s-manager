// KeychainAdapter.swift — infrastructure adapter placeholder
// Implements: CredentialStorePort from SharedKernel
// Library: Security.framework (Apple system framework — no SwiftPM package)
// Status: skeleton; port implementations pending domain ports definition.
import Security
import SharedKernel
import Foundation

/// Namespace marker for the KeychainAdapter adapter target.
///
/// Concrete actor types implementing the domain ports land under this enum
/// in subsequent rounds. This file exists so the target compiles cleanly
/// under Swift 6 strict concurrency with the imported infrastructure library.
public enum KeychainAdapter: Sendable {
    public static let moduleVersion = "0.0.1-skeleton"
}

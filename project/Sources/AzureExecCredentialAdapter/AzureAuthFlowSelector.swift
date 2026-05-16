// AzureAuthFlowSelector.swift — AzureExecCredentialAdapter target
// DDD role: Infrastructure helper (flow discriminator)
// ADR-0018 §Azure/AKS authentication protocol

import Foundation

// MARK: - AzureAuthFlow

/// Discriminates the MSAL acquisition flow to use for a given set of
/// kubeconfig auth-provider configuration values.
///
/// Resolution order (first match wins):
/// 1. ``servicePrincipalSecret`` when `clientSecret` is non-empty.
/// 2. ``servicePrincipalCertificate`` when `certificatePath` is non-empty.
/// 3. ``deviceCode`` — interactive operator sign-in fallback.
public enum AzureAuthFlow: Equatable, Sendable {
    /// Confidential-client credential grant using a client secret.
    case servicePrincipalSecret(clientSecret: String)

    /// Confidential-client credential grant using a PEM/PKCS12 certificate.
    case servicePrincipalCertificate(certificatePath: String)

    /// Interactive device-code flow for operator sign-in.
    case deviceCode
}

// MARK: - AzureAuthFlowSelector

/// Pure, stateless value that picks the correct MSAL flow given kubeconfig
/// auth-provider configuration values.
///
/// All inputs arrive as optional strings because kubeconfig `authProvider.config`
/// is an untyped string-to-string dictionary.
public struct AzureAuthFlowSelector: Sendable {
    /// The tenant (directory) identifier from the kubeconfig auth-provider
    /// config block (`tenantId`).
    public let tenantId: String

    /// The application (client) identifier (`clientId`).
    public let clientId: String

    /// Optional client secret for service-principal authentication.
    public let clientSecret: String?

    /// Optional path to a PEM or PKCS12 certificate for service-principal
    /// certificate authentication.
    public let certificatePath: String?

    // MARK: Init

    /// Creates a selector from raw kubeconfig auth-provider config values.
    ///
    /// - Parameters:
    ///   - tenantId: Entra ID tenant identifier.
    ///   - clientId: Application (client) identifier.
    ///   - clientSecret: Optional client secret; empty strings are treated as absent.
    ///   - certificatePath: Optional path to a certificate; empty strings are treated as absent.
    public init(
        tenantId: String,
        clientId: String,
        clientSecret: String? = nil,
        certificatePath: String? = nil
    ) {
        self.tenantId = tenantId
        self.clientId = clientId
        self.clientSecret = clientSecret.flatMap { $0.isEmpty ? nil : $0 }
        self.certificatePath = certificatePath.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Flow resolution

    /// Resolves the authentication flow to use.
    ///
    /// Resolution order:
    /// 1. ``AzureAuthFlow/servicePrincipalSecret(_:)`` when `clientSecret` is present.
    /// 2. ``AzureAuthFlow/servicePrincipalCertificate(_:)`` when `certificatePath` is present.
    /// 3. ``AzureAuthFlow/deviceCode`` — interactive operator sign-in fallback.
    public func resolve() -> AzureAuthFlow {
        if let secret = clientSecret {
            return .servicePrincipalSecret(clientSecret: secret)
        }
        if let certPath = certificatePath {
            return .servicePrincipalCertificate(certificatePath: certPath)
        }
        return .deviceCode
    }
}

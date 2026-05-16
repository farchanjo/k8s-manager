// AWSExecCredentialAdapter.swift — infrastructure adapter
// Bounded context: cluster_connectivity / AWS EKS IAM authenticator
// DDD role: Adapter (outbound — ExecPluginPort implementation)
// ADR reference: ADR-0018 §AWS EKS authentication protocol
//
// Protocol: EKS IAM authenticator — pre-signed STS GetCallerIdentity URL
// encoded as a `k8s-aws-v1.` prefixed bearer token.
// Subprocess-free: satisfies ADR-0001 (notarisation-safe distribution).
//
// Swift 6 strict concurrency — `public struct … Sendable`.
// SotoCore / SotoSTS are not in Swift 6 language mode; the `@preconcurrency`
// import isolates the annotation to this adapter boundary per ADR-0018.

@preconcurrency import SotoCore
@preconcurrency import SotoSTS
import ClusterConnectivity
import Foundation
import Logging

// MARK: - AWSCredentialError

/// Errors that the AWS EKS credential adapter can throw.
public enum AWSCredentialError: Error, Sendable {
    /// The `args` array did not contain a recognisable `--cluster-name` value.
    case missingClusterName

    /// The `args` array did not contain a recognisable `--region` value.
    case missingRegion

    /// The STS endpoint URL could not be constructed for the resolved region.
    case invalidEndpointURL(region: String)

    /// The pre-signed URL could not be base64url-encoded.
    case encodingFailure(detail: String)
}

// MARK: - AWSExecCredentialAdapter

/// EKS IAM authenticator credential adapter.
///
/// Resolves Kubernetes bearer tokens for Amazon EKS clusters by constructing a
/// SigV4 pre-signed STS `GetCallerIdentity` URL and encoding it as a
/// `k8s-aws-v1.`-prefixed token. No subprocess is invoked; the adapter
/// satisfies ADR-0001 (subprocess-free, notarisation-safe) and ADR-0018
/// (native AWS credential resolution).
///
/// The Soto credential-provider chain resolves credentials from:
/// 1. Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
///    `AWS_SESSION_TOKEN`, `AWS_WEB_IDENTITY_TOKEN_FILE`).
/// 2. `~/.aws/credentials` and `~/.aws/config` with optional `--profile`.
/// 3. SSO / IAM Identity Center (soto `.sso()` provider — read-only; SSO
///    login browser flow is not initiated, matching ADR-0018 MVP scope).
/// 4. macOS Login keychain (`soto` `.login()` provider).
///
/// AssumeRole and IRSA (AssumeRoleWithWebIdentity) chains are handled
/// transparently by the soto environment provider.
public struct AWSExecCredentialAdapter: ExecPluginPort, Sendable {

    // MARK: Properties

    /// Soto credential-provider factory injected at construction time.
    ///
    /// Defaults to `.default`, which on macOS resolves:
    /// environment → `~/.aws` config files → SSO → login keychain.
    private let credentialProviderFactory: CredentialProviderFactory

    /// Logger for this adapter instance.
    private let logger: Logger

    // MARK: Initialisation

    /// Creates an adapter with the default Soto credential-provider chain.
    ///
    /// - Parameter logger: Logger to attach to all AWS API calls made by this
    ///   adapter. Defaults to a `"aws-exec-credential"` labelled logger.
    public init(logger: Logger = Logger(label: "aws-exec-credential")) {
        self.credentialProviderFactory = .default
        self.logger = logger
    }

    /// Creates an adapter with an injected credential-provider factory.
    ///
    /// Intended for unit tests that want to supply `.static(...)` or `.empty`
    /// credentials without touching the host machine's AWS configuration files.
    ///
    /// - Parameters:
    ///   - credentialProviderFactory: Soto factory used to resolve AWS
    ///     credentials (e.g. `.static(accessKeyId:secretAccessKey:)` in tests).
    ///   - logger: Logger attached to all AWS API calls.
    public init(
        credentialProviderFactory: CredentialProviderFactory,
        logger: Logger = Logger(label: "aws-exec-credential")
    ) {
        self.credentialProviderFactory = credentialProviderFactory
        self.logger = logger
    }

    // MARK: ExecPluginPort

    /// Resolves an EKS bearer token from the STS GetCallerIdentity pre-signed URL.
    ///
    /// Parses `--cluster-name` and `--region` from `auth.args`, builds a
    /// SigV4 pre-signed URL for the regional STS endpoint, then encodes the
    /// result as a `k8s-aws-v1.`-prefixed base64url (no-padding) string.
    ///
    /// - Parameter auth: Exec-plugin parameters from the kubeconfig user entry.
    ///   `auth.args` must contain `--cluster-name <name>` and
    ///   `--region <region>`. `auth.env` may override `AWS_PROFILE`.
    /// - Returns: `.bearerToken` `AuthInfo` carrying the EKS token.
    /// - Throws: `AWSCredentialError` when arguments are missing; throws
    ///   `AWSClient.ClientError` on signing failures.
    public func resolve(auth: ExecPluginAuth) async throws -> AuthInfo {
        let clusterName = try extractArg("--cluster-name", from: auth.args)
        let regionString = try extractArg("--region", from: auth.args)
        let profile = extractOptionalArg("--profile", from: auth.args)
            ?? envVar("AWS_PROFILE", overrides: auth.env)

        let token = try await buildEKSToken(
            clusterName: clusterName,
            regionString: regionString,
            profile: profile
        )
        return .bearerToken(BearerTokenAuth(token: token))
    }

    // MARK: Private helpers — token construction

    private func buildEKSToken(
        clusterName: String,
        regionString: String,
        profile: String?
    ) async throws -> String {
        let region = Region(rawValue: regionString)

        // When a profile is explicitly requested build a factory that uses it;
        // otherwise fall through to whatever factory was injected at init time.
        let factory: CredentialProviderFactory = profile.map {
            .selector(.environment, .configFile(profile: $0), .sso(profileName: $0))
        } ?? credentialProviderFactory

        let client = AWSClient(
            credentialProvider: factory,
            logger: logger
        )
        defer {
            Task {
                try? await client.shutdown()
            }
        }

        let sts = STS(client: client, region: region)

        guard let endpointURL = stsEndpointURL(region: regionString) else {
            throw AWSCredentialError.invalidEndpointURL(region: regionString)
        }

        // The `x-k8s-aws-id` header must be included in the signed URL so the
        // EKS authenticator webhook can extract the cluster name without trusting
        // the operator's environment. Soto encodes the header into the
        // `X-Amz-SignedHeaders` query parameter automatically.
        let headers = HTTPHeaders([("x-k8s-aws-id", clusterName)])
        let signedURL = try await sts.client.signURL(
            url: endpointURL,
            httpMethod: .GET,
            headers: headers,
            expires: .seconds(60),
            serviceConfig: sts.config,
            logger: logger
        )

        return try encodeToken(signedURL: signedURL)
    }

    // MARK: Private helpers — URL construction

    /// Builds the STS `GetCallerIdentity` URL for the target region.
    ///
    /// Uses the regional endpoint (`sts.<region>.amazonaws.com`) rather than
    /// the global `sts.amazonaws.com` endpoint so that the token is valid for
    /// clusters in the correct partition (standard / GovCloud / China).
    private func stsEndpointURL(region: String) -> URL? {
        let host: String
        if region.hasPrefix("cn-") {
            host = "sts.\(region).amazonaws.com.cn"
        } else {
            // Covers standard + GovCloud (us-gov-*) — both use amazonaws.com.
            host = "sts.\(region).amazonaws.com"
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "Action", value: "GetCallerIdentity"),
            URLQueryItem(name: "Version", value: "2011-06-15"),
        ]
        return components.url
    }

    // MARK: Private helpers — token encoding

    /// Base64url-encodes the signed URL (no padding) and prepends `k8s-aws-v1.`.
    ///
    /// Matches the token format accepted by the Kubernetes `aws-iam-authenticator`
    /// webhook and `aws eks get-token` output.
    private func encodeToken(signedURL: URL) throws -> String {
        let urlString = signedURL.absoluteString
        guard let data = urlString.data(using: .utf8) else {
            throw AWSCredentialError.encodingFailure(detail: "URL is not UTF-8 representable")
        }
        let base64url = data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "k8s-aws-v1.\(base64url)"
    }

    // MARK: Private helpers — argument parsing

    /// Extracts a required named argument from the `args` array.
    ///
    /// Supports both `--flag value` and `--flag=value` forms.
    private func extractArg(_ flag: String, from args: [String]) throws -> String {
        if let value = extractOptionalArg(flag, from: args) {
            return value
        }
        switch flag {
        case "--cluster-name": throw AWSCredentialError.missingClusterName
        case "--region": throw AWSCredentialError.missingRegion
        default: throw AWSCredentialError.missingClusterName
        }
    }

    /// Extracts an optional named argument from the `args` array.
    private func extractOptionalArg(_ flag: String, from args: [String]) -> String? {
        for (index, arg) in args.enumerated() {
            if arg == flag, index + 1 < args.count {
                return args[index + 1]
            }
            let prefix = "\(flag)="
            if arg.hasPrefix(prefix) {
                return String(arg.dropFirst(prefix.count))
            }
        }
        return nil
    }

    /// Resolves a variable name against the exec-plugin override env list first,
    /// falling back to `nil` (Soto reads `ProcessInfo` directly for the rest).
    private func envVar(_ name: String, overrides: [EnvVar]) -> String? {
        overrides.first { $0.name == name }?.value
    }
}

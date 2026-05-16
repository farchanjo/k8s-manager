// Domain/ProviderProfile.swift — llm_provider bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/llm_provider/schemas/provider_profile.cue
// ADR ref: ADR-0045 (ProviderProfile.localOnly + endpoint validation)

import Foundation
import SharedKernel

// MARK: - ProviderKind

/// The provider wire protocol this profile targets.
///
/// Mirrors the `kind` discriminant in `#ProviderProfile`.
public enum ProviderKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// Anthropic Messages API (`POST /v1/messages`).
    case anthropic

    /// OpenAI Chat Completions or Responses API.
    case openai

    /// OpenAI-compatible endpoint with a configurable `baseURL`.
    case openaiCompatible = "openai_compatible"
}

// MARK: - SamplingConfig

/// Sampling knobs forwarded verbatim to the provider adapter.
///
/// Mirrors `#SamplingConfig` from `provider_profile.cue`. Immutable value
/// object — produced by the operator settings surface.
public struct SamplingConfig: Hashable, Sendable, Codable {
    /// Temperature in `[0.0, 2.0]`.
    public let temperature: Double

    /// Nucleus sampling parameter in `(0.0, 1.0]`. Adapter-specific default
    /// when `nil`.
    public let topP: Double?

    /// Top-k sampling limit. Adapter-specific default when `nil`.
    public let topK: Int?

    /// Hard token cap for the completion. Must be in `(0, 128000]`.
    public let maxOutputTokens: Int

    /// Stop sequences injected into every request for this profile.
    public let stopSequences: [String]

    /// Provider-specific opt-ins (e.g., `"anthropic_prompt_caching": "ephemeral"`).
    public let providerHints: [String: String]

    public init(
        temperature: Double,
        topP: Double? = nil,
        topK: Int? = nil,
        maxOutputTokens: Int,
        stopSequences: [String] = [],
        providerHints: [String: String] = [:]
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxOutputTokens = maxOutputTokens
        self.stopSequences = stopSequences
        self.providerHints = providerHints
    }
}

// MARK: - ProviderProfile

/// Operator-configured LLM provider entry.
///
/// Mirrors `#ProviderProfile` from `provider_profile.cue`. The aggregate root
/// for the `llm_provider` context — persisted by `local_persistence`. The API
/// key is never stored inline; `keyAlias` is a Keychain reference resolved by
/// `LLMKeyStorePort` at request time.
public struct ProviderProfile: Hashable, Sendable, Codable {
    /// UUIDv7-shaped stable identifier. Never changes on rename.
    public let id: UUID

    /// Operator-chosen label. 1–80 characters.
    public let displayName: String

    /// Provider wire protocol.
    public let kind: ProviderKind

    /// Required for `openaiCompatible`; ignored (not stored) for other kinds.
    /// The adapter resolves the canonical URL at request time for
    /// `anthropic` and `openai`.
    public let baseURL: URL?

    /// Provider-side model identifier (e.g., `"claude-sonnet-4-6"`).
    public let modelId: String

    /// Keychain entry reference. NEVER the key value itself.
    public let keyAlias: String

    /// Default sampling parameters applied when the caller does not override.
    public let samplingDefaults: SamplingConfig

    /// RFC3339 creation timestamp.
    public let createdAtRFC3339: String

    /// RFC3339 last-modified timestamp.
    public let updatedAtRFC3339: String

    /// When `true`, the adapter is allowed to connect to loopback / localhost
    /// endpoints only. When `false` (default), the endpoint must not be a
    /// link-local, private, or loopback address (ADR-0045).
    public let localOnly: Bool

    public init(
        id: UUID,
        displayName: String,
        kind: ProviderKind,
        baseURL: URL? = nil,
        modelId: String,
        keyAlias: String,
        samplingDefaults: SamplingConfig,
        createdAtRFC3339: String,
        updatedAtRFC3339: String,
        localOnly: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.baseURL = baseURL
        self.modelId = modelId
        self.keyAlias = keyAlias
        self.samplingDefaults = samplingDefaults
        self.createdAtRFC3339 = createdAtRFC3339
        self.updatedAtRFC3339 = updatedAtRFC3339
        self.localOnly = localOnly
    }

    // MARK: - Endpoint validation (ADR-0045)

    /// Validates the ``baseURL`` of an `openaiCompatible` profile against
    /// ADR-0045 network-topology rules.
    ///
    /// Rules when `localOnly == false`:
    /// - Rejects IPv6 link-local (`fe80::/10`).
    /// - Rejects IPv4 link-local (`169.254.x.x`).
    /// - Rejects `.local` and `.internal` mDNS suffixes.
    /// - Rejects private CIDRs: `10.x.x.x`, `172.16–31.x.x`, `192.168.x.x`.
    /// - Rejects loopback range `127.0.0.0/8` and `0.0.0.0`.
    ///
    /// Rules when `localOnly == true`:
    /// - Only `localhost`, `127.0.0.1`, or `[::1]` with port 1024–65535
    ///   are accepted.
    ///
    /// Non-`openaiCompatible` profiles (Anthropic, OpenAI) use the vendor
    /// canonical URL and are exempt from validation.
    ///
    /// - Throws: ``EndpointValidationError`` when the endpoint violates policy.
    public func validateEndpoint() throws {
        guard kind == .openaiCompatible, let url = baseURL else { return }
        let host = (url.host ?? "").lowercased()
        let port = url.port ?? (url.scheme == "https" ? 443 : 80)

        if localOnly {
            try validateLocalOnlyEndpoint(host: host, port: port)
        } else {
            try validatePublicEndpoint(host: host)
        }
    }

    // MARK: Private helpers

    private func validateLocalOnlyEndpoint(host: String, port: Int) throws {
        let allowed = host == "localhost" || host == "127.0.0.1" || host == "[::1]"
        guard allowed else {
            throw EndpointValidationError.nonLoopbackInLocalOnlyProfile(host: host)
        }
        guard (1024...65535).contains(port) else {
            throw EndpointValidationError.portOutOfRange(port: port)
        }
    }

    private func validatePublicEndpoint(host: String) throws {
        // Loopback and unspecified
        if host == "localhost" || host == "127.0.0.1" || host == "[::1]" {
            throw EndpointValidationError.loopbackNotAllowed(host: host)
        }
        if host == "0.0.0.0" {
            throw EndpointValidationError.unspecifiedAddressNotAllowed
        }
        // mDNS suffixes
        if host.hasSuffix(".local") || host.hasSuffix(".internal") {
            throw EndpointValidationError.disallowedHostSuffix(host: host)
        }
        // IPv6 link-local (fe80::/10)
        if host.hasPrefix("fe80") {
            throw EndpointValidationError.ipv6LinkLocal(host: host)
        }
        // IPv4 checks
        if let ipv4Parts = parseIPv4(host) {
            try validateIPv4Parts(ipv4Parts, host: host)
        }
        // 127.x.x.x range (loopback /8 beyond 127.0.0.1)
        if let first = parseIPv4(host)?.first, first == 127 {
            throw EndpointValidationError.loopbackNotAllowed(host: host)
        }
    }

    private func validateIPv4Parts(_ parts: [Int], host: String) throws {
        guard parts.count == 4 else { return }
        let (a, b) = (parts[0], parts[1])
        // 127.x.x.x
        if a == 127 { throw EndpointValidationError.loopbackNotAllowed(host: host) }
        // 10.x.x.x
        if a == 10 { throw EndpointValidationError.privateNetworkNotAllowed(host: host) }
        // 172.16–31.x.x
        if a == 172, (16...31).contains(b) {
            throw EndpointValidationError.privateNetworkNotAllowed(host: host)
        }
        // 192.168.x.x
        if a == 192, b == 168 {
            throw EndpointValidationError.privateNetworkNotAllowed(host: host)
        }
        // 169.254.x.x (IPv4 link-local)
        if a == 169, b == 254 {
            throw EndpointValidationError.ipv4LinkLocal(host: host)
        }
    }

    /// Parses a dotted-decimal IPv4 string into its four integer octets.
    /// Returns `nil` for hostnames and malformed strings.
    private func parseIPv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else {
            return nil
        }
        return parts
    }
}

// MARK: - EndpointValidationError

/// Errors thrown by ``ProviderProfile/validateEndpoint()`` (ADR-0045).
public enum EndpointValidationError: Error, Sendable, Equatable {
    /// The profile is `localOnly` but the endpoint resolves to a non-loopback host.
    case nonLoopbackInLocalOnlyProfile(host: String)
    /// The port is outside the unprivileged range [1024, 65535].
    case portOutOfRange(port: Int)
    /// A loopback address was supplied in a non-`localOnly` profile.
    case loopbackNotAllowed(host: String)
    /// `0.0.0.0` is not a routable endpoint.
    case unspecifiedAddressNotAllowed
    /// `.local` or `.internal` mDNS suffix.
    case disallowedHostSuffix(host: String)
    /// IPv6 link-local prefix `fe80::/10`.
    case ipv6LinkLocal(host: String)
    /// RFC 1918 private-network CIDR.
    case privateNetworkNotAllowed(host: String)
    /// IPv4 link-local `169.254.x.x`.
    case ipv4LinkLocal(host: String)
}

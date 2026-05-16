// ADCLoader.swift — GCPExecCredentialAdapter
// Reads Application Default Credentials JSON from disk and returns a typed
// credential value. Path resolution follows the ADC specification:
//   1. $GOOGLE_APPLICATION_CREDENTIALS (env override)
//   2. ~/.config/gcloud/application_default_credentials.json (well-known path)

import Foundation
import Logging

// MARK: - ADCCredential

/// Typed representation of a parsed Application Default Credentials file.
public enum ADCCredential: Sendable {
    /// OAuth2 user credentials (refresh-token grant).
    case userCredentials(UserADC)

    /// Service-account JSON key (RS256 JWT → token endpoint).
    case serviceAccount(ServiceAccountADC)

    /// External account / Workload Identity Federation.
    case externalAccount(ExternalAccountADC)
}

// MARK: - UserADC

/// Fields from an ADC file with `"type": "authorized_user"`.
public struct UserADC: Sendable {
    public let clientID: String
    public let clientSecret: String
    public let refreshToken: String

    public init(clientID: String, clientSecret: String, refreshToken: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
    }
}

// MARK: - ServiceAccountADC

/// Fields from an ADC file with `"type": "service_account"`.
public struct ServiceAccountADC: Sendable {
    public let clientEmail: String
    public let privateKey: String        // PEM-encoded RSA private key
    public let privateKeyID: String
    public let tokenURI: String

    public init(
        clientEmail: String,
        privateKey: String,
        privateKeyID: String,
        tokenURI: String
    ) {
        self.clientEmail = clientEmail
        self.privateKey = privateKey
        self.privateKeyID = privateKeyID
        self.tokenURI = tokenURI
    }
}

// MARK: - ExternalAccountADC

/// Minimum fields from an ADC file with `"type": "external_account"`.
/// Full WIF support is deferred; only the raw JSON blob is preserved for the
/// stub error path.
public struct ExternalAccountADC: Sendable {
    public let tokenURL: String
    public let audience: String

    public init(tokenURL: String, audience: String) {
        self.tokenURL = tokenURL
        self.audience = audience
    }
}

// MARK: - ADCLoaderError

/// Errors raised during ADC file loading and parsing.
public enum ADCLoaderError: Error, Sendable {
    /// No ADC file found at either the env-override path or the well-known path.
    case fileNotFound(path: String)

    /// The ADC file could not be decoded as valid JSON.
    case invalidJSON(detail: String)

    /// The `type` field in the ADC file is unrecognised.
    case unknownCredentialType(type: String)

    /// A required field is missing from the ADC file.
    case missingField(field: String)
}

// MARK: - ADCLoader

/// Reads and parses an Application Default Credentials JSON file.
public struct ADCLoader: Sendable {

    private let logger: Logger

    public init(logger: Logger = Logger(label: "gcp.adc-loader")) {
        self.logger = logger
    }

    // MARK: - Public API

    /// Loads ADC from the resolved path and returns a typed credential.
    ///
    /// - Parameter overridePath: When non-nil, bypasses the standard path-
    ///   resolution chain and loads from this exact path. Used in tests.
    /// - Returns: The parsed `ADCCredential`.
    /// - Throws: `ADCLoaderError` when the file cannot be found or parsed.
    public func load(overridePath: String? = nil) async throws -> ADCCredential {
        let resolvedPath = overridePath ?? self.resolveADCPath()
        logger.debug("Loading ADC from \(resolvedPath)")

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: resolvedPath))
        } catch {
            throw ADCLoaderError.fileNotFound(path: resolvedPath)
        }

        return try self.parse(data: data)
    }

    // MARK: - Private helpers

    private func resolveADCPath() -> String {
        if let envPath = ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"],
           !envPath.isEmpty {
            return envPath
        }
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/.config/gcloud/application_default_credentials.json"
    }

    private func parse(data: Data) throws -> ADCCredential {
        let raw: [String: Any]
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ADCLoaderError.invalidJSON(detail: "Root value is not a JSON object")
            }
            raw = dict
        } catch let error as ADCLoaderError {
            throw error
        } catch {
            throw ADCLoaderError.invalidJSON(detail: error.localizedDescription)
        }

        guard let type = raw["type"] as? String else {
            throw ADCLoaderError.missingField(field: "type")
        }

        switch type {
        case "authorized_user":
            return .userCredentials(try parseUserADC(raw))
        case "service_account":
            return .serviceAccount(try parseServiceAccountADC(raw))
        case "external_account":
            return .externalAccount(try parseExternalAccountADC(raw))
        default:
            throw ADCLoaderError.unknownCredentialType(type: type)
        }
    }

    private func parseUserADC(_ raw: [String: Any]) throws -> UserADC {
        guard let clientID = raw["client_id"] as? String else {
            throw ADCLoaderError.missingField(field: "client_id")
        }
        guard let clientSecret = raw["client_secret"] as? String else {
            throw ADCLoaderError.missingField(field: "client_secret")
        }
        guard let refreshToken = raw["refresh_token"] as? String else {
            throw ADCLoaderError.missingField(field: "refresh_token")
        }
        return UserADC(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken)
    }

    private func parseServiceAccountADC(_ raw: [String: Any]) throws -> ServiceAccountADC {
        guard let clientEmail = raw["client_email"] as? String else {
            throw ADCLoaderError.missingField(field: "client_email")
        }
        guard let privateKey = raw["private_key"] as? String else {
            throw ADCLoaderError.missingField(field: "private_key")
        }
        guard let privateKeyID = raw["private_key_id"] as? String else {
            throw ADCLoaderError.missingField(field: "private_key_id")
        }
        let tokenURI = (raw["token_uri"] as? String) ?? "https://oauth2.googleapis.com/token"
        return ServiceAccountADC(
            clientEmail: clientEmail,
            privateKey: privateKey,
            privateKeyID: privateKeyID,
            tokenURI: tokenURI
        )
    }

    private func parseExternalAccountADC(_ raw: [String: Any]) throws -> ExternalAccountADC {
        guard let tokenURL = raw["token_url"] as? String else {
            throw ADCLoaderError.missingField(field: "token_url")
        }
        guard let audience = raw["audience"] as? String else {
            throw ADCLoaderError.missingField(field: "audience")
        }
        return ExternalAccountADC(tokenURL: tokenURL, audience: audience)
    }
}

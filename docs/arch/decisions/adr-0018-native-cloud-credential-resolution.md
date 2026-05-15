# ADR-0018 — Native cloud credential resolution (AWS/GCP/Azure/OIDC)

- Status — Proposed
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — auth, credentials, aws, gcp, azure, oidc, hexagonal, exec-plugin
- Supersedes-partially — ADR-0002 (exec credential plugin clause)

## Context and problem statement

ADR-0001 commits K8sManager to a fully native macOS distribution with no
dependency on external binaries. ADR-0002 initially deferred the
implementation of exec credential plugins to subprocess invocation,
allowing the app to call `aws eks get-token`, `gke-gcloud-auth-plugin`,
`kubelogin`, and similar CLI tools installed on the operator's machine.

That approach contradicts the distribution goal stated in ADR-0001: a
Developer-ID notarised, sandboxable application must not rely on
third-party binaries whose presence, version, and PATH visibility are
outside the application's control. Operators who install K8sManager via
the eventual App Store distribution cannot be expected to also install
the AWS CLI, gcloud SDK, or kubelogin. The subprocess approach also
introduces observable startup latency (fork, exec, credential round-trip)
on every token refresh, which degrades the experience of users managing
many clusters.

The problem is therefore: how does K8sManager obtain short-lived bearer
tokens for clusters that use the AWS EKS IAM authenticator, GCP
Application Default Credentials, Azure Active Directory / Entra ID, or
generic OIDC providers — without invoking any subprocess — while
maintaining backward compatibility for custom exec plugins that fall
outside these four well-known patterns?

## Decision drivers

- Subprocess-free: no fork/exec of aws, gcloud, gke-gcloud-auth-plugin,
  kubelogin, or any other CLI tool during normal operation.
- Notarisation-safe: all network calls go through URLSession or
  async-http-client (both allowed under com.apple.security.network.client
  entitlement). No arbitrary executable launch entitlement needed.
- Backward compatibility: kubeconfigs that declare an exec credential
  plugin whose name is not one of the four known patterns must continue
  to work via a subprocess fallback adapter (capability-flagged, emits a
  log warning). This preserves ADR-0002 semantics for the unknown-plugin
  case.
- Hexagonal architecture: the domain core must not reference any cloud
  SDK or HTTP library. All credential acquisition logic lives in adapter
  layer targets. The domain core exposes only an `ExecCredentialPort`
  interface returning an opaque `BearerToken` value type.
- Incremental delivery: the four backends (AWS, GCP, Azure, OIDC) can be
  implemented and shipped independently. The domain port and the
  subprocess fallback adapter ship first; native adapters replace the
  fallback as they reach production readiness.
- Swift 6 strict concurrency: every adapter must compile clean under
  `-strict-concurrency=complete`. Third-party libraries that are not yet
  Swift 6 language-mode compliant must be wrapped in isolated adapter
  modules that do not leak `@preconcurrency` into the domain core.

## Considered options

- Option A — Implement all four credential backends natively in Swift,
  with a subprocess fallback adapter for unknown exec plugin names.
- Option B — Retain subprocess invocation for all exec credential
  plugins (ADR-0002 original behaviour). No native implementation.
- Option C — Implement only AWS natively (highest user demand); retain
  subprocess for GCP, Azure, and OIDC.

## Decision outcome

Chosen option: Option A — native implementation for all four well-known
backends with subprocess fallback for unknown exec plugin names.

Option B is rejected because it permanently blocks sandbox and App Store
distribution, introduces binary-version fragility, and is incompatible
with ADR-0001 goals.

Option C is rejected because it creates an inconsistent user experience:
operators managing mixed AWS + GCP or AWS + Azure clusters would still
need CLI tooling installed. The effort difference between A and C is
approximately 10 to 14 weeks (GCP + Azure + OIDC), which is acceptable
given the project timeline.

### Consequences

Positive consequences:

- K8sManager can authenticate to EKS, GKE, and AKS clusters on a fresh
  macOS installation with no prerequisites beyond valid credential files
  or active SSO sessions.
- Token refresh is in-process and low-latency (no fork/exec overhead).
- Operator experience is consistent across cloud providers.
- Application can eventually be distributed via the Mac App Store without
  requiring com.apple.security.temporary-exception.files.absolute-path
  or similar sandbox escapes.

Negative consequences:

- Total native implementation effort is approximately 5 to 6 months of
  dedicated engineering time across all four backends. This is a
  significant commitment that must be planned across multiple release
  milestones.
- Maintaining native GCP credential resolution is now the
  responsibility of the K8sManager team, because
  google-auth-library-swift was archived in October 2025 and is no
  longer maintained by Google.
- Three libraries used by the Azure and OIDC backends (MSAL,
  AppAuth-iOS) are not yet in Swift 6 language mode. They require
  `@preconcurrency import` at the adapter boundary and must be wrapped
  so that the annotation does not propagate to domain core targets.
- The subprocess fallback adapter must be security-reviewed before
  shipping: it accepts an arbitrary executable path from the kubeconfig
  and will spawn it. The adapter must validate the resolved path against
  known safe locations, log a prominent warning, and document the
  sandboxing implications.

### Confirmation

The following integration tests must pass before this ADR is considered
accepted:

- A kubeconfig that uses `command: aws` with `args: [eks, get-token]`
  and valid AWS credentials in the environment resolves a bearer token
  without invoking any aws binary. The AWS adapter uses SigV4 pre-signed
  STS GetCallerIdentity and returns a `k8s-aws-v1.` prefixed token.
- A kubeconfig that uses `command: gke-gcloud-auth-plugin` and a valid
  `application_default_credentials.json` on disk resolves an access
  token via the Google OAuth2 token endpoint without invoking any gcloud
  binary.
- A kubeconfig that uses `command: kubelogin` and valid Azure
  credentials resolves a bearer token via MSAL without invoking any
  kubelogin binary.
- A kubeconfig with an unrecognised exec plugin name triggers the
  subprocess fallback adapter, logs a warning containing the plugin
  name, and successfully returns the token produced by the subprocess.
- All four native adapters compile without warnings under
  `-strict-concurrency=complete` and `-language-mode 6`.

## Pros and cons of the options

### Option A — Native total (chosen)

Positive:

- Fully subprocess-free: compatible with sandbox and App Store
  distribution.
- In-process token refresh: lower latency than fork/exec on every
  cluster connection.
- Decouples K8sManager from operator-installed CLI tool versions.
- GCP adapter built in-house gives full control over ADC chain and
  Workload Identity Federation without depending on an archived library.

Negative:

- High implementation effort: approximately 5 to 6 months across all
  four backends.
- GCP maintenance burden is entirely on the K8sManager team from day 1.
- MSAL and AppAuth-iOS add `@preconcurrency` wrapper complexity.
- STS pre-signing and GCP JWT signing require careful cryptographic
  correctness; bugs may produce silent auth failures against live
  clusters.

### Option B — Subprocess exec plugins (ADR-0002 original)

Positive:

- Zero implementation effort for credential acquisition: delegate
  entirely to installed CLI tools.
- CLI tools are maintained by AWS, Google, and Microsoft.

Negative:

- Blocks sandbox and App Store distribution permanently.
- Requires operators to install and maintain aws, gcloud, kubelogin on
  every machine where K8sManager runs.
- Subprocess invocation introduces fork/exec latency on every token
  refresh cycle.
- Exec plugin PATH resolution is fragile under macOS Launch Agent
  process environments where the user's shell PATH is not inherited.
- Contradicts ADR-0001 distribution goals.

### Option C — Hybrid (native AWS only, subprocess for others)

Positive:

- Reduces initial implementation effort to approximately 6 weeks (AWS
  backend only).
- AWS is the highest-volume use case; most operators benefit immediately.

Negative:

- GCP, Azure, and OIDC operators still require installed CLI tools.
- Creates inconsistent user experience: some providers work natively,
  others require subprocess.
- Defers a known technical debt that must eventually be addressed to
  reach App Store distribution.
- Does not eliminate the sandboxing limitation.

## More information

### AWS EKS authentication protocol

The AWS EKS IAM authenticator accepts a pre-signed STS `GetCallerIdentity`
URL as a bearer token. The adapter must:

1. Resolve credentials from the chain: environment variables
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`
   and `AWS_PROFILE`, then `~/.aws/credentials` and `~/.aws/config`
   parsed by soto-project/soto 7.14.0 credential providers.
2. Construct a STS `GetCallerIdentity` request for the target region.
3. Pre-sign the request URL with SigV4 query parameter signature and a
   TTL of 60 seconds.
4. Add the `x-k8s-aws-id: <cluster-name>` header encoded into the
   pre-signed URL.
5. Base64URL-encode the full pre-signed URL (no padding).
6. Prefix the result with the literal `k8s-aws-v1.`.
7. Return the prefixed string as the bearer token value.

AssumeRole and AssumeRoleWithWebIdentity (IRSA) chains are handled
transparently by the soto credential provider chain before step 1.

AWS SSO and IAM Identity Center are deferred to a post-MVP release.
Operators using SSO can use the subprocess fallback adapter in the
interim.

The fallback library is `awslabs/aws-sdk-swift` 1.6.x (official AWS
SDK). It is used only if soto 7.14.0 does not cover a required
credential provider variant discovered during integration testing.

### GCP / GKE authentication protocol

The google-auth-library-swift library was archived by Google in October
2025. The adapter is implemented manually and must support three
credential sources defined by the Application Default Credentials (ADC)
specification:

- User credentials: `~/.config/gcloud/application_default_credentials.json`
  with `client_id`, `client_secret`, and `refresh_token`. The adapter
  exchanges the refresh token at `https://oauth2.googleapis.com/token`
  for a short-lived access token using URLSession.
- Service account JSON key: a JSON file with `type: service_account`,
  `private_key_id`, and a PEM-encoded RSA private key. The adapter
  constructs a JWT signed with RS256 using vapor/jwt-kit 5.5.0 and
  apple/swift-crypto CryptoExtras (RSA sign operation), then exchanges
  it at `https://oauth2.googleapis.com/token`.
- External account (Workload Identity Federation): a JSON file with
  `type: external_account` and a `credential_source` block. The adapter
  calls the specified external token endpoint, then exchanges the result
  at the Google STS endpoint defined in `token_url`.

The ADC file path is resolved from the environment variable
`GOOGLE_APPLICATION_CREDENTIALS` first, then the well-known path.

### Azure / AKS authentication protocol

The adapter uses MSAL for macOS (AzureAD/microsoft-authentication-library-for-objc
2.11.0, MIT licence). MSAL covers:

- Interactive device code flow for operator sign-in sessions.
- Service principal with client secret: confidential client credential
  flow.
- Service principal with client certificate: confidential client with
  X.509 certificate assertion.

Managed Identity (IMDS) and Workload Identity (Azure federated credentials)
are implemented manually via direct HTTP to
`http://169.254.169.254/metadata/identity/oauth2/token` and the Azure
AD federated identity endpoint respectively. These cases are rare on
macOS developer workstations but required for completeness.

MSAL requires macOS 11+. K8sManager targets macOS 14+, so this
constraint is not binding.

### OIDC generic authentication protocol

The adapter uses AppAuth-iOS / AppAuth-macOS
(openid/AppAuth-iOS 2.0.0, Apache 2.0). It implements:

- Authorization Code flow with PKCE for interactive sign-in.
- Refresh token grant for silent token renewal.
- OIDC discovery: the adapter fetches
  `<issuer>/.well-known/openid-configuration` to locate the token
  endpoint and JWKS URI.
- ID token validation: the adapter fetches the JWKS document and
  verifies the token signature using vapor/jwt-kit 5.5.0.

The adapter stores the refresh token in the macOS Keychain via the
`KeychainAdapter` target (see ADR-0010).

### Domain port and adapter registry

The domain port is:

```
ClusterConnectivity/Sources/ClusterConnectivity/Ports/ExecCredentialPort.swift
```

It declares a single async throwing method that accepts a kubeconfig
`ExecConfig` value (command name, arguments, environment, API version)
and returns a `BearerToken` sendable value type.

The adapter registry in the `K8sManagerApp` executable target maps
exec plugin command names to concrete adapter implementations:

- `aws` (or `aws-iam-authenticator`) maps to `AWSExecCredentialAdapter`.
- `gke-gcloud-auth-plugin` maps to `GCPExecCredentialAdapter`.
- `kubelogin` maps to `AzureExecCredentialAdapter`.
- Any plugin returning `client.authentication.k8s.io/v1` with an OIDC
  audience hint maps to `OIDCExecCredentialAdapter`.
- All other command names map to `SubprocessExecCredentialAdapter`
  with a logged warning.

The registry is injected via pointfreeco/swift-dependencies, allowing
test targets to override specific adapters without modifying the
application wiring.

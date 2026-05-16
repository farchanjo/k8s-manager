// Views/Resources/Config/DockerConfigInspector.swift — app_shell bounded context
// DDD role: View
// ADR refs: ADR-0063 (secret reveal/hide + dockerconfigjson parser §Special type parsers)

import SwiftUI

// MARK: - DockerConfigInspector

/// Renders the parsed `kubernetes.io/dockerconfigjson` structure as a table.
///
/// Each row shows the registry hostname, username, and a masked password
/// column. Each password cell has its own `SecretRevealButton` with the
/// dotted-path key name `.dockerconfigjson.auths.<registry>.password`.
///
/// If the caller provides `parseError`, the view falls back to an inline
/// error badge per ADR-0063 §Parsing rules step 2.
@MainActor
public struct DockerConfigInspector: View {

    // MARK: Properties

    let config: DockerConfigJSON?
    let parseError: DockerConfigParseError?

    /// Set of registry keys whose passwords are currently revealed.
    /// Key format matches `SecretRevealButton.keyName` for audit path.
    @Binding var revealedPasswords: Set<String>

    let onRevealPassword: (_ registryKey: String) -> Void
    let onHidePassword: (_ registryKey: String) -> Void

    // MARK: Init

    /// Creates a `DockerConfigInspector`.
    ///
    /// - Parameters:
    ///   - config: The parsed docker config value; `nil` triggers error display.
    ///   - parseError: The parse error when config could not be parsed.
    ///   - revealedPasswords: Binding to the set of currently revealed registry
    ///     password keys (each key is a registry hostname string).
    ///   - onRevealPassword: Called with the registry key when the operator
    ///     reveals a password.
    ///   - onHidePassword: Called with the registry key when the operator
    ///     hides a password.
    public init(
        config: DockerConfigJSON?,
        parseError: DockerConfigParseError?,
        revealedPasswords: Binding<Set<String>>,
        onRevealPassword: @escaping (String) -> Void,
        onHidePassword: @escaping (String) -> Void
    ) {
        self.config = config
        self.parseError = parseError
        self._revealedPasswords = revealedPasswords
        self.onRevealPassword = onRevealPassword
        self.onHidePassword = onHidePassword
    }

    // MARK: Body

    public var body: some View {
        if let error = parseError {
            errorBadge(error)
        } else if let config {
            registryTable(config)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: Private views

    @ViewBuilder
    private func registryTable(_ cfg: DockerConfigJSON) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            if cfg.registries.isEmpty {
                Text("No registries found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(cfg.registries, id: \.registry) { entry in
                    registryRow(entry)
                    Divider().opacity(0.5)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Registry").frame(maxWidth: .infinity, alignment: .leading)
            Text("Username").frame(width: 120, alignment: .leading)
            Text("Password").frame(width: 120, alignment: .leading)
            Spacer().frame(width: 28)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private func registryRow(_ entry: DockerConfigRegistry) -> some View {
        let isRevealed = revealedPasswords.contains(entry.registry)
        return HStack(spacing: 0) {
            Text(entry.registry)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.username ?? "\u{2014}")
                .frame(width: 120, alignment: .leading)
            passwordCell(entry: entry, isRevealed: isRevealed)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func passwordCell(entry: DockerConfigRegistry, isRevealed: Bool) -> some View {
        HStack(spacing: 6) {
            if isRevealed {
                Text(entry.password ?? "\u{2014}")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 108, alignment: .leading)
            } else {
                Text(entry.password != nil ? "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}" : "\u{2014}")
                    .frame(width: 108, alignment: .leading)
            }
            SecretRevealButton(
                keyName: ".dockerconfigjson.auths.\(entry.registry).password",
                isRevealed: isRevealed,
                onReveal: { onRevealPassword(entry.registry) },
                onHide: { onHidePassword(entry.registry) }
            )
        }
    }

    private func errorBadge(_ error: DockerConfigParseError) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            switch error {
            case .invalidJSON:
                Text("Invalid JSON — raw value shown.")
                    .font(.caption)
            case .missingAuthsMap:
                Text("Missing auths map — raw value shown.")
                    .font(.caption)
            }
        }
    }
}

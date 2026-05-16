// Views/Resources/Config/SecretRevealButton.swift — app_shell bounded context
// DDD role: View
// ADR refs: ADR-0063 (secret reveal/hide + dockerconfigjson parser §Reveal flow contract)

import SwiftUI

// MARK: - SecretRevealButton

/// An eye-icon toggle button that reveals or hides a single Secret data key.
///
/// Accessibility labels follow the ADR-0063 contract:
/// - Masked state: "Reveal value for key \(keyName)"
/// - Revealed state: "Hide value for key \(keyName)"
///
/// The button does not perform the audit write itself; it calls the provided
/// `onReveal` / `onHide` closures, allowing the parent view model to handle
/// the port call and state management.
public struct SecretRevealButton: View {

    // MARK: Properties

    let keyName: String
    let isRevealed: Bool
    let onReveal: () -> Void
    let onHide: () -> Void

    // MARK: Init

    /// Creates a `SecretRevealButton`.
    ///
    /// - Parameters:
    ///   - keyName: The Secret data key name (used in accessibility labels).
    ///   - isRevealed: Current visibility state.
    ///   - onReveal: Called when the operator clicks to reveal the value.
    ///   - onHide: Called when the operator clicks to hide the revealed value.
    public init(
        keyName: String,
        isRevealed: Bool,
        onReveal: @escaping () -> Void,
        onHide: @escaping () -> Void
    ) {
        self.keyName = keyName
        self.isRevealed = isRevealed
        self.onReveal = onReveal
        self.onHide = onHide
    }

    // MARK: Body

    public var body: some View {
        Button {
            if isRevealed {
                onHide()
            } else {
                onReveal()
            }
        } label: {
            Image(systemName: isRevealed ? "eye.slash" : "eye")
                .foregroundStyle(isRevealed ? .secondary : .primary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    // MARK: Private

    private var accessibilityLabel: String {
        if isRevealed {
            return "Hide value for key \(keyName)"
        } else {
            return "Reveal value for key \(keyName)"
        }
    }
}

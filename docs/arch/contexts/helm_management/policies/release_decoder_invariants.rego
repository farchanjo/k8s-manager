package helm_management.release_decoder

# DDD role: DomainService
#
# release_decoder_invariants is the Rego policy that governs whether a
# Kubernetes Secret may be decoded into a #Release aggregate. The policy
# is evaluated by the ReleaseDecoderPort adapter before any materialisation
# of the aggregate. If any deny rule fires, the Secret is rejected and the
# operator is presented with a structured error rather than partial or
# incorrect release data.
#
# The evaluating adapter calls this policy with the following input shape:
#
#   input.secretType          — the Kubernetes Secret type string
#                               (e.g. "helm.sh/release.v1")
#   input.ownerLabel          — the value of the "owner" label on the Secret
#                               (e.g. "helm")
#   input.hasReleaseBlob      — boolean: true if data["release"] key is present
#                               and non-empty in the Secret
#   input.decompressionOk     — boolean: true if the base64+gzip decode of
#                               data["release"] completed without error
#   input.manifestYAML        — the rendered manifest string extracted from
#                               the decoded release JSON; empty string if
#                               decompression failed
#
# Policy result: allow is true when no deny rule fires. Any populated
# deny_reasons set causes the adapter to reject the Secret entirely.
#
# SECURITY NOTE: the embedded_credential_detected rule is a defence-in-depth
# guard. Charts MUST NOT embed PEM credential material in rendered manifests;
# if they do, this is a bug in the chart. K8sManager rejects such Secrets
# rather than displaying potentially sensitive data.

# Default: reject the Secret unless every allow condition is satisfied.
default allow := false

allow {
    count(deny_reasons) == 0
}

# deny_reasons aggregates all active denial messages. The adapter surfaces
# these to the operator for diagnostic purposes.
deny_reasons[msg] { msg := wrong_type }
deny_reasons[msg] { msg := wrong_owner }
deny_reasons[msg] { msg := missing_release_blob }
deny_reasons[msg] { msg := decompression_failed }
deny_reasons[msg] { msg := embedded_credential_detected }

# ---------------------------------------------------------------------------
# Rule: wrong_type
#
# The Kubernetes Secret type must be exactly "helm.sh/release.v1". Any
# other Secret type indicates that this Secret is not a Helm release record
# and must not be decoded as one.
# ---------------------------------------------------------------------------
wrong_type := msg {
    input.secretType != "helm.sh/release.v1"
    msg := sprintf(
        "secret type %q is not \"helm.sh/release.v1\"; not a Helm release Secret",
        [input.secretType]
    )
}

# ---------------------------------------------------------------------------
# Rule: wrong_owner
#
# The "owner" label must equal "helm". This label is set by the Helm 3
# secret storage driver on every release Secret. Its absence or wrong value
# indicates a Secret that was not created by Helm.
# ---------------------------------------------------------------------------
wrong_owner := msg {
    input.ownerLabel != "helm"
    msg := sprintf(
        "label \"owner\" is %q; expected \"helm\"; not a Helm-managed Secret",
        [input.ownerLabel]
    )
}

# ---------------------------------------------------------------------------
# Rule: missing_release_blob
#
# The Secret must contain a "release" key in its data map. The Helm secret
# driver always writes this key. A missing or empty key indicates a
# corrupted or partial Secret.
# ---------------------------------------------------------------------------
missing_release_blob := msg {
    not input.hasReleaseBlob
    msg := "Secret data[\"release\"] key is absent or empty; cannot decode Helm release"
}

# ---------------------------------------------------------------------------
# Rule: decompression_failed
#
# The base64-decode plus gunzip of the release blob must complete without
# error. A failure indicates data corruption, truncation, or a format change
# in the Helm release serialisation (e.g., a Helm version mismatch).
# ---------------------------------------------------------------------------
decompression_failed := msg {
    input.hasReleaseBlob
    not input.decompressionOk
    msg := "base64+gzip decompression of data[\"release\"] failed; Secret data may be corrupted"
}

# ---------------------------------------------------------------------------
# Rule: embedded_credential_detected
#
# The rendered manifest YAML must not contain PEM-encoded certificate or
# private key blocks. A PEM block beginning with "-----BEGIN " in the
# manifest is a signal that the chart has incorrectly embedded credential
# material in a rendered resource (e.g., a TLS Secret rendered inline, a
# self-signed CA embedded in a ConfigMap). K8sManager rejects such Secrets
# as a defence-in-depth measure to prevent accidental display of private keys
# or certificates in the release detail view.
#
# This rule fires only when decompression succeeded (manifest is available).
# If decompression failed, the decompression_failed rule already fires.
# ---------------------------------------------------------------------------
embedded_credential_detected := msg {
    input.decompressionOk
    contains(input.manifestYAML, "-----BEGIN ")
    msg := "rendered manifest contains PEM-encoded credential material (-----BEGIN ...); Secret rejected for security; this indicates a chart bug"
}

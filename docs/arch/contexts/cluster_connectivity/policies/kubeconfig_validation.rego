# DDD role: Policy
package cluster_connectivity.kubeconfig_validation

# DDD role: Policy
#
# These Rego rules validate a #Kubeconfig aggregate after it has been
# parsed from disk. Violations are surfaced to the operator in the
# kubeconfig load report and do not prevent the application from
# starting, but unhealthy contexts are marked accordingly in the UI.

# A kubeconfig MUST declare apiVersion and kind.
deny[msg] {
    input.apiVersion != "v1"
    msg := sprintf("apiVersion must be v1, got %q", [input.apiVersion])
}

deny[msg] {
    input.kind != "Config"
    msg := sprintf("kind must be Config, got %q", [input.kind])
}

# currentContext, when set, MUST reference an existing context entry.
deny[msg] {
    input.currentContext != ""
    not context_exists(input.currentContext)
    msg := sprintf("currentContext %q is not declared under contexts[]", [input.currentContext])
}

context_exists(name) {
    some i
    input.contexts[i].name == name
}

# Every context MUST reference an existing cluster and user.
deny[msg] {
    some i
    ctx := input.contexts[i]
    not cluster_exists(ctx.cluster)
    msg := sprintf("contexts[%d].cluster %q is not declared under clusters[]", [i, ctx.cluster])
}

deny[msg] {
    some i
    ctx := input.contexts[i]
    not user_exists(ctx.user)
    msg := sprintf("contexts[%d].user %q is not declared under users[]", [i, ctx.user])
}

cluster_exists(name) {
    some i
    input.clusters[i].name == name
}

user_exists(name) {
    some i
    input.users[i].name == name
}

# An insecure-skip-tls-verify cluster MUST also include a warning
# annotation in the load report. This is enforced as a warning, not
# a deny, since legitimate development clusters frequently set it.
warn[msg] {
    some i
    cluster := input.clusters[i]
    cluster.insecureSkipTLSVerify == true
    msg := sprintf("clusters[%d] %q sets insecureSkipTLSVerify=true; credentials will not be remembered across sessions", [i, cluster.name])
}

# Exactly one credential strategy per user.
deny[msg] {
    some i
    user := input.users[i]
    count(credential_strategies(user)) != 1
    msg := sprintf("users[%d] %q must declare exactly one credential strategy, found %d", [i, user.name, count(credential_strategies(user))])
}

credential_strategies(user) := strategies {
    strategies := {s |
        s := "client_cert";    user.clientCertificateData
    } | {s |
        s := "client_cert";    user.clientCertificatePath
    } | {s |
        s := "bearer_token";   user.token
    } | {s |
        s := "bearer_token";   user.tokenFile
    } | {s |
        s := "exec_plugin";    user.exec
    }
}

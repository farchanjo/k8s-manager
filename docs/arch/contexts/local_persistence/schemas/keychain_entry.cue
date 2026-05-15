// DDD role: ValueObject
package local_persistence

// #KeychainEntry is the value-object representation of a single
// Keychain item managed by the application. The application stores
// only LLM API keys in Keychain; kubeconfig material is never
// copied here (ADR-0003).
#KeychainEntry: {
	// service is constant for all entries managed by this app.
	service!: "com.archanjo.K8sManager.llm"

	// account is the keyAlias declared on a ProviderProfile. The
	// alias is a slug, not a secret.
	account!: =~"^[a-z0-9][a-z0-9_\\-]*$"

	// accessControl is the macOS access-control descriptor applied
	// at item creation.
	accessControl!: "kSecAttrAccessibleWhenUnlockedThisDeviceOnly"

	// label is the user-friendly description shown in
	// Keychain Access.
	label!: =~"^K8sManager LLM key - .+$"

	// genericPasswordSizeBytes is the upper bound (16 KiB) on the
	// stored secret payload; the schema does not record the secret
	// itself.
	genericPasswordSizeBytes!: int & >0 & <=16384
}

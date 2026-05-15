// DDD role: ValueObject
package local_persistence

// #AuditChainKey is the value-object representation of the Keychain item
// that holds the HMAC-SHA256 key for the mutation audit chain.
//
// The key itself is never present in this schema (it is a secret held
// exclusively in the macOS Keychain). This schema describes the shape of
// the Keychain item attributes used by AuditChainKeyManager to locate,
// create, and validate the key item.
//
// References: ADR-0047 (audit chain HMAC), ADR-0010 (Keychain access policy).
#AuditChainKey: {
	// service is the kSecAttrService value for all audit chain key items.
	// Distinct from the LLM key service ("com.archanjo.K8sManager.llm")
	// declared in #KeychainEntry to ensure the two key families are
	// namespace-separated in Keychain Access.
	service!: "com.archanjo.K8sManager.audit"

	// account is the kSecAttrAccount discriminator for this key version.
	// A new account string will be introduced for each key rotation
	// generation (e.g. "chain-mac-key-v2" for the second generation).
	account!: =~"^chain-mac-key-v[0-9]+$"

	// accessControl is the macOS access-control descriptor applied at
	// item creation time. WhenUnlockedThisDeviceOnly ensures:
	//   (a) the key is unavailable when the screen is locked,
	//   (b) the key is never migrated to iCloud Keychain or transferred
	//       to another device via backup/restore.
	accessControl!: "kSecAttrAccessibleWhenUnlockedThisDeviceOnly"

	// label is the human-readable description shown in Keychain Access.
	// Must unambiguously identify the item to a system administrator.
	label!: =~"^K8sManager audit chain MAC key - v[0-9]+$"

	// algorithm is the MAC algorithm for which this key is used.
	// Fixed at HMAC-SHA256 for v1; future versions may use HMAC-SHA512
	// and will carry a distinct account string and label.
	algorithm!: "HMAC-SHA256"

	// keyLengthBits is the number of bits in the stored key material.
	// Must be 256 for HMAC-SHA256 (one SHA-256 block width).
	keyLengthBits!: 256

	// keyVersion is the monotonically increasing generation counter,
	// matching the suffix in the account field. Starts at 1.
	keyVersion!: int & >=1
}

// auditChainKeyV1 is the canonical instance for the first key generation.
// AuditChainKeyManager uses these attribute values when creating or
// looking up the Keychain item.
auditChainKeyV1: #AuditChainKey & {
	service:       "com.archanjo.K8sManager.audit"
	account:       "chain-mac-key-v1"
	accessControl: "kSecAttrAccessibleWhenUnlockedThisDeviceOnly"
	label:         "K8sManager audit chain MAC key - v1"
	algorithm:     "HMAC-SHA256"
	keyLengthBits: 256
	keyVersion:    1
}

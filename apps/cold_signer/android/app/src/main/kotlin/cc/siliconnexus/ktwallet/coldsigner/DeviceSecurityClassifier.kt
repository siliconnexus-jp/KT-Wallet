package cc.siliconnexus.ktwallet.coldsigner

/** Pure fail-closed classification kept outside Android services for tests. */
internal object DeviceSecurityClassifier {
    fun network(activeNetworkPresent: Boolean, capabilitiesAvailable: Boolean): String = when {
        !activeNetworkPresent -> "safe"
        !capabilitiesAvailable -> "unknown"
        else -> "unsafe"
    }

    fun integrity(rootEvidence: Boolean): String = if (rootEvidence) "unsafe" else "unknown"
}

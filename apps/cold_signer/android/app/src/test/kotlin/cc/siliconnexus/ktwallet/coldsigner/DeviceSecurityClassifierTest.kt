package cc.siliconnexus.ktwallet.coldsigner

import org.junit.Assert.assertEquals
import org.junit.Test

class DeviceSecurityClassifierTest {
    @Test
    fun noActiveNetworkIsSafe() {
        assertEquals("safe", DeviceSecurityClassifier.network(false, false))
    }

    @Test
    fun anyResolvedActiveNetworkIsUnsafeEvenWithoutInternetCapability() {
        assertEquals("unsafe", DeviceSecurityClassifier.network(true, true))
    }

    @Test
    fun unresolvedActiveNetworkIsUnknownNotSafe() {
        assertEquals("unknown", DeviceSecurityClassifier.network(true, false))
    }

    @Test
    fun absenceOfRootEvidenceNeverClaimsIntegrityIsSafe() {
        assertEquals("unsafe", DeviceSecurityClassifier.integrity(true))
        assertEquals("unknown", DeviceSecurityClassifier.integrity(false))
    }
}

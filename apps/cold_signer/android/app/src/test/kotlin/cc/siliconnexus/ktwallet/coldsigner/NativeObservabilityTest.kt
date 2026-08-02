package cc.siliconnexus.ktwallet.coldsigner

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeObservabilityTest {
    @Test
    fun reportsOnlyAForegroundMainThreadStall() {
        assertFalse(NativeStallDetector.shouldReport(12_000, 1_000, false, false, false))
        assertFalse(NativeStallDetector.shouldReport(12_000, 1_000, true, true, false))
        assertFalse(NativeStallDetector.shouldReport(12_000, 1_000, true, false, true))
        assertFalse(NativeStallDetector.shouldReport(9_999, 1_000, true, false, false))
        assertTrue(NativeStallDetector.shouldReport(11_000, 1_000, true, false, false))
    }
}

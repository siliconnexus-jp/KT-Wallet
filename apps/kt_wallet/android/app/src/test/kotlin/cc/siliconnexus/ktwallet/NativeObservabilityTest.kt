package cc.siliconnexus.ktwallet

import java.io.ByteArrayInputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
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

    @Test
    fun selectedBackupReadIsStrictlyBounded() {
        val exact = ByteArray(32) { it.toByte() }
        assertArrayEquals(exact, readPickedFileBounded(ByteArrayInputStream(exact), exact.size))

        try {
            readPickedFileBounded(ByteArrayInputStream(ByteArray(33)), 32)
            fail("oversized input must be rejected")
        } catch (_: PickedFileTooLargeException) {
            // Expected: the 33rd byte is observed but never copied to Dart.
        }
    }
}

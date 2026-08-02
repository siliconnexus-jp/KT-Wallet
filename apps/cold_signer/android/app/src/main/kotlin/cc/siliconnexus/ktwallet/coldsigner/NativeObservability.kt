package cc.siliconnexus.ktwallet.coldsigner

import android.content.Context
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

internal data class NativeIncident(val id: Long, val kind: String)

internal object NativeStallDetector {
    const val THRESHOLD_MS = 10_000L

    fun shouldReport(
        nowMs: Long,
        lastMainTickMs: Long,
        foreground: Boolean,
        debuggerAttached: Boolean,
        alreadyReported: Boolean
    ): Boolean = foreground &&
        !debuggerAttached &&
        !alreadyReported &&
        nowMs - lastMainTickMs >= THRESHOLD_MS
}

internal class NativeIncidentStore(context: Context) {
    private val preferences =
        context.getSharedPreferences("kt.native-observability.v1", Context.MODE_PRIVATE)

    @Synchronized
    fun record(kind: String) {
        if (kind != "fatal" && kind != "anr") return
        val current = decode(preferences.getString(EVENTS_KEY, null))
        val nextId = preferences.getLong(NEXT_ID_KEY, 1L).coerceAtLeast(1L)
        val bounded = (current + NativeIncident(nextId, kind)).takeLast(MAX_EVENTS)
        preferences.edit()
            .putLong(NEXT_ID_KEY, nextId + 1L)
            .putString(EVENTS_KEY, encode(bounded))
            .commit()
    }

    @Synchronized
    fun pendingPayload(): Map<String, Any> = mapOf(
        "schemaVersion" to 1,
        "events" to decode(preferences.getString(EVENTS_KEY, null)).map {
            mapOf("id" to it.id, "kind" to it.kind)
        }
    )

    @Synchronized
    fun acknowledge(throughId: Long): Boolean {
        if (throughId <= 0L) return false
        val remaining = decode(preferences.getString(EVENTS_KEY, null))
            .filter { it.id > throughId }
        return preferences.edit().putString(EVENTS_KEY, encode(remaining)).commit()
    }

    private fun encode(events: List<NativeIncident>) =
        events.joinToString(",") { "${it.id}:${it.kind}" }

    private fun decode(encoded: String?): List<NativeIncident> {
        if (encoded.isNullOrEmpty()) return emptyList()
        return encoded.split(',').mapNotNull { row ->
            val parts = row.split(':')
            val id = parts.getOrNull(0)?.toLongOrNull()
            val kind = parts.getOrNull(1)
            if (parts.size == 2 && id != null && id > 0 &&
                (kind == "fatal" || kind == "anr")
            ) NativeIncident(id, kind) else null
        }.sortedBy { it.id }.takeLast(MAX_EVENTS)
    }

    private companion object {
        const val EVENTS_KEY = "events"
        const val NEXT_ID_KEY = "next-id"
        const val MAX_EVENTS = 32
    }
}

internal class NativeAnrWatchdog(private val store: NativeIncidentStore) {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var running = true
    @Volatile private var foreground = false
    @Volatile private var lastMainTickMs = SystemClock.uptimeMillis()
    @Volatile private var reportedForCurrentStall = false

    private val tick = object : Runnable {
        override fun run() {
            lastMainTickMs = SystemClock.uptimeMillis()
            reportedForCurrentStall = false
            if (running) mainHandler.postDelayed(this, POLL_MS)
        }
    }

    private val monitor = Thread({
        while (running) {
            try {
                Thread.sleep(POLL_MS)
            } catch (_: InterruptedException) {
                continue
            }
            if (NativeStallDetector.shouldReport(
                    SystemClock.uptimeMillis(),
                    lastMainTickMs,
                    foreground,
                    Debug.isDebuggerConnected(),
                    reportedForCurrentStall
                )
            ) {
                reportedForCurrentStall = true
                store.record("anr")
            }
        }
    }, "kt-native-watchdog").apply {
        isDaemon = true
        start()
    }

    init {
        mainHandler.post(tick)
    }

    fun setForeground(value: Boolean) {
        foreground = value
        if (value) {
            lastMainTickMs = SystemClock.uptimeMillis()
            reportedForCurrentStall = false
        }
    }

    fun stop() {
        running = false
        mainHandler.removeCallbacks(tick)
        monitor.interrupt()
    }

    private companion object {
        const val POLL_MS = 2_000L
    }
}

internal class NativeFatalObserver(private val store: NativeIncidentStore) {
    fun install() {
        synchronized(NativeFatalObserver::class.java) {
            if (installed) return
            installed = true
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                store.record("fatal")
                previous?.uncaughtException(thread, throwable)
            }
        }
    }

    private companion object {
        @Volatile var installed = false
    }
}

package com.ktwallet.cold_signer

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity): local_auth's BiometricPrompt
// requires a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The standalone signer is always displaying secrets (mnemonics, the
        // signing QR loop), so FLAG_SECURE is set unconditionally: no
        // screenshots, no screen recording, blanked recents preview.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}

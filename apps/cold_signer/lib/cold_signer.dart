/// Embeddable entry point for the Cold Signer experience.
///
/// The combined single-installer app (kt_wallet) imports this library to run
/// the full signer experience behind its device-mode picker. Only the app
/// widget is exported — `main()` stays the standalone entrypoint.
library;

export 'main.dart' show ColdSignerApp;

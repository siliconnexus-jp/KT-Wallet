import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Why a save did not happen, so the UI can say something useful instead of a
/// bare failure.
enum SaveImageOutcome {
  saved,

  /// The user declined the photo-library permission.
  denied,

  /// The platform cannot do a permission-free save here (Android below 29),
  /// so the caller should offer sharing instead.
  unsupported,

  failed,
}

/// Writes a generated image into the device's photo library.
///
/// Behind a MethodChannel rather than a plugin: the two platform paths are
/// small, and the dependency firewall keeps third-party packages out unless
/// they earn their place.
class MediaGallery {
  const MediaGallery();

  static MediaGallery instance = const MediaGallery();

  @visibleForTesting
  static const channel = MethodChannel('kt/media');

  Future<SaveImageOutcome> saveImage(
    Uint8List png, {
    required String name,
  }) async {
    try {
      final ok = await channel.invokeMethod<bool>('saveImage', {
        'bytes': png,
        'name': name,
      });
      return ok == true ? SaveImageOutcome.saved : SaveImageOutcome.failed;
    } on MissingPluginException {
      // No handler (tests, desktop): treat as "offer sharing instead".
      return SaveImageOutcome.unsupported;
    } on PlatformException catch (e) {
      return switch (e.code) {
        'PERMISSION_DENIED' => SaveImageOutcome.denied,
        'UNSUPPORTED' => SaveImageOutcome.unsupported,
        _ => SaveImageOutcome.failed,
      };
    }
  }
}

/// Records calls instead of touching the platform.
class FakeMediaGallery implements MediaGallery {
  FakeMediaGallery({this.outcome = SaveImageOutcome.saved});

  final SaveImageOutcome outcome;
  final List<({Uint8List png, String name})> saved = [];

  @override
  Future<SaveImageOutcome> saveImage(
    Uint8List png, {
    required String name,
  }) async {
    saved.add((png: png, name: name));
    return outcome;
  }
}

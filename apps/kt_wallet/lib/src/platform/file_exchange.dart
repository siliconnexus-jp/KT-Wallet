import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How a save or pick ended. Cancelling is not a failure and must not be
/// reported as one — the user closing the Files sheet is a decision, not a bug.
enum FileExchangeOutcome { done, cancelled, unsupported, failed }

/// Result of a save.
///
/// Deliberately just the outcome. Naming the destination back to the user
/// sounds helpful but is not: the picker gives us a sandbox URL, whose last
/// components are a container UUID, not the "iCloud Drive" the user saw
/// themselves when they chose it.
class SavedFile {
  const SavedFile(this.outcome);

  final FileExchangeOutcome outcome;
}

class PickedFile {
  const PickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Hands a file to the system document picker and takes one back.
///
/// On iOS this is `UIDocumentPickerViewController`, which is what puts
/// "iCloud Drive" in front of the user — and it needs no iCloud entitlement,
/// no CloudKit container and no provisioning change, because the user chooses
/// the destination themselves. On Android it is the Storage Access Framework,
/// where the same sheet offers Drive and any other installed provider.
///
/// A MethodChannel rather than a plugin, matching [MediaGallery]: both paths
/// are short, and the dependency firewall keeps third-party packages out
/// unless they earn their place.
class FileExchange {
  const FileExchange();

  static FileExchange instance = const FileExchange();

  @visibleForTesting
  static const channel = MethodChannel('kt/files');

  /// Presents the system "save to…" sheet. [suggestedName] is pre-filled and
  /// the user may change it.
  Future<SavedFile> saveFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    try {
      final res = await channel.invokeMapMethod<String, Object?>('saveFile', {
        'name': suggestedName,
        'bytes': bytes,
      });
      if (res == null) return const SavedFile(FileExchangeOutcome.failed);
      if (res['cancelled'] == true) {
        return const SavedFile(FileExchangeOutcome.cancelled);
      }
      return const SavedFile(FileExchangeOutcome.done);
    } on MissingPluginException {
      // No handler (tests, desktop, an older shell): say unsupported rather
      // than failed, so the caller can offer another route.
      return const SavedFile(FileExchangeOutcome.unsupported);
    } on PlatformException catch (e) {
      return SavedFile(
        e.code == 'CANCELLED'
            ? FileExchangeOutcome.cancelled
            : FileExchangeOutcome.failed,
      );
    }
  }

  /// Presents the system file picker. Returns null when the user cancels.
  ///
  /// [extensions] filters what is selectable; an empty list allows anything.
  Future<PickedFile?> pickFile({List<String> extensions = const []}) async {
    try {
      final res = await channel.invokeMapMethod<String, Object?>('pickFile', {
        'extensions': extensions,
      });
      if (res == null || res['cancelled'] == true) return null;
      final bytes = res['bytes'];
      if (bytes is! Uint8List) return null;
      return PickedFile(name: (res['name'] as String?) ?? '', bytes: bytes);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// Keeps whatever it was handed and replays a scripted pick.
class FakeFileExchange implements FileExchange {
  FakeFileExchange({this.saveOutcome = FileExchangeOutcome.done, this.pick});

  final FileExchangeOutcome saveOutcome;
  PickedFile? pick;

  final List<({String name, Uint8List bytes})> saved = [];
  int pickCount = 0;

  @override
  Future<SavedFile> saveFile({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    saved.add((name: suggestedName, bytes: bytes));
    return SavedFile(saveOutcome);
  }

  @override
  Future<PickedFile?> pickFile({List<String> extensions = const []}) async {
    pickCount++;
    return pick;
  }
}

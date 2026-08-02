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

const pickedFileDisplayNameMaxRunes = 80;

/// Reduces a provider-controlled document identifier to a safe display name.
/// The value is presentation only and is never used to reopen the document.
String sanitizePickedFileName(Object? value) {
  if (value is! String || value.isEmpty) return '';
  final slash = value.lastIndexOf('/');
  final backslash = value.lastIndexOf(r'\');
  final leaf = value.substring((slash > backslash ? slash : backslash) + 1);
  final cleaned = <int>[];
  var previousWasSpace = false;
  for (final rune in leaf.runes) {
    final forbidden =
        rune <= 0x1F ||
        (rune >= 0x7F && rune <= 0x9F) ||
        rune == 0x061C ||
        (rune >= 0x200B && rune <= 0x200F) ||
        (rune >= 0x2028 && rune <= 0x202E) ||
        rune == 0x2060 ||
        (rune >= 0x2066 && rune <= 0x2069) ||
        rune == 0xFEFF;
    if (forbidden) continue;
    final spaceLike =
        rune == 0x20 ||
        rune == 0xA0 ||
        rune == 0x1680 ||
        (rune >= 0x2000 && rune <= 0x200A) ||
        rune == 0x202F ||
        rune == 0x205F ||
        rune == 0x3000;
    if (spaceLike) {
      if (cleaned.isNotEmpty && !previousWasSpace) cleaned.add(0x20);
      previousWasSpace = true;
      continue;
    }
    cleaned.add(rune);
    previousWasSpace = false;
  }
  while (cleaned.isNotEmpty && cleaned.last == 0x20) {
    cleaned.removeLast();
  }
  if (cleaned.isEmpty) return '';
  if (cleaned.length > pickedFileDisplayNameMaxRunes) {
    const suffixRunes = 23;
    final prefixRunes = pickedFileDisplayNameMaxRunes - suffixRunes - 1;
    final shortened = <int>[
      ...cleaned.take(prefixRunes),
      0x2026,
      ...cleaned.skip(cleaned.length - suffixRunes),
    ];
    return String.fromCharCodes(shortened);
  }
  final name = String.fromCharCodes(cleaned);
  return name == '.' || name == '..' ? '' : name;
}

/// The selected document exceeded the bounded read requested by the caller.
/// This is distinct from cancellation so the UI can explain why nothing was
/// imported without exposing a provider path or diagnostic.
class FileTooLargeException implements Exception {
  const FileTooLargeException();
}

enum FilePickFailure { unavailable, failed }

/// The system document picker could not be opened or could not return the
/// selected bytes. Cancellation is represented by `null`; keeping failures as
/// exceptions prevents an iCloud/Drive/provider outage from looking like the
/// user simply dismissed the sheet.
class FilePickException implements Exception {
  const FilePickException(this.failure);

  final FilePickFailure failure;
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
  Future<PickedFile?> pickFile({
    List<String> extensions = const [],
    required int maxBytes,
  }) async {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    try {
      final res = await channel.invokeMapMethod<String, Object?>('pickFile', {
        'extensions': extensions,
        'maxBytes': maxBytes,
      });
      if (res == null) throw const FilePickException(FilePickFailure.failed);
      if (res['cancelled'] == true) return null;
      final bytes = res['bytes'];
      if (bytes is! Uint8List) {
        throw const FilePickException(FilePickFailure.failed);
      }
      if (bytes.length > maxBytes) throw const FileTooLargeException();
      return PickedFile(
        name: sanitizePickedFileName(res['name']),
        bytes: bytes,
      );
    } on MissingPluginException {
      throw const FilePickException(FilePickFailure.unavailable);
    } on PlatformException catch (error) {
      if (error.code == 'FILE_TOO_LARGE') {
        throw const FileTooLargeException();
      }
      throw const FilePickException(FilePickFailure.failed);
    } on FileTooLargeException {
      rethrow;
    } on FilePickException {
      rethrow;
    } catch (_) {
      // A native implementation returning the wrong channel shape is a
      // failure, never cancellation. Do not expose the cast/runtime error.
      throw const FilePickException(FilePickFailure.failed);
    }
  }
}

/// Keeps whatever it was handed and replays a scripted pick.
class FakeFileExchange implements FileExchange {
  FakeFileExchange({
    this.saveOutcome = FileExchangeOutcome.done,
    this.pick,
    this.pickFailure,
  });

  final FileExchangeOutcome saveOutcome;
  PickedFile? pick;
  FilePickException? pickFailure;

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
  Future<PickedFile?> pickFile({
    List<String> extensions = const [],
    required int maxBytes,
  }) async {
    pickCount++;
    final failure = pickFailure;
    if (failure != null) throw failure;
    final selected = pick;
    if (selected != null && selected.bytes.length > maxBytes) {
      throw const FileTooLargeException();
    }
    return selected == null
        ? null
        : PickedFile(
            name: sanitizePickedFileName(selected.name),
            bytes: selected.bytes,
          );
  }
}

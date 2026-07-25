import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// External platform actions used by link and share affordances.
///
/// Kept behind an interface so widget tests never need plugin MethodChannels.
abstract class ExternalActions {
  const ExternalActions();

  static ExternalActions instance = const PlatformExternalActions();

  Future<bool> open(Uri uri);

  Future<void> share({required String text, String? subject});
}

class PlatformExternalActions extends ExternalActions {
  const PlatformExternalActions();

  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<void> share({required String text, String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}

class FakeExternalActions extends ExternalActions {
  FakeExternalActions({this.openResult = true});

  final bool openResult;
  final List<Uri> opened = [];
  final List<({String text, String? subject})> shared = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return openResult;
  }

  @override
  Future<void> share({required String text, String? subject}) async {
    shared.add((text: text, subject: subject));
  }
}

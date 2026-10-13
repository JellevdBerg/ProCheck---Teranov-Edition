import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// GitHub's "latest release" endpoint for this repo — unauthenticated, so
/// it's subject to GitHub's low (60/hr) anonymous rate limit, which is fine
/// for a once-per-session check.
const _latestReleaseUrl =
    'https://api.github.com/repos/jellevdberg/procheck---teranov-edition/releases/latest';

const _checkTimeout = Duration(seconds: 5);

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.releaseUrl,
    this.assetName,
    this.assetUrl,
    this.checksumsUrl,
  });

  /// The new version's number (no leading "v"), e.g. "1.1.0".
  final String version;
  final String releaseNotes;
  final String releaseUrl;

  /// This platform's build zip and the release's `SHA256SUMS.txt` — null when
  /// the release has no matching asset (the updater then falls back to
  /// opening [releaseUrl]).
  final String? assetName;
  final String? assetUrl;
  final String? checksumsUrl;
}

/// Picks this platform's zip and the checksums file out of a release's
/// `assets` array (names are set in `.github/workflows/release.yml`).
({String? name, String? url, String? checksums}) pickReleaseAssets(
  Object? assets,
  String platform,
) {
  String? name, url, checksums;
  if (assets is List) {
    for (final a in assets.whereType<Map<String, dynamic>>()) {
      final n = a['name'];
      final u = a['browser_download_url'];
      if (n is! String || u is! String) continue;
      if (n == 'SHA256SUMS.txt') checksums = u;
      if (n.startsWith('procheck-$platform-') && n.endsWith('.zip')) {
        name = n;
        url = u;
      }
    }
  }
  return (name: name, url: url, checksums: checksums);
}

String? get _updatePlatform =>
    Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'macos' : null);

/// Whether the user has dismissed this session's update banner — reset on
/// every app launch, never persisted.
final updateBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Checks GitHub Releases once per app launch (or on manual refresh via
/// [WidgetRef.refresh]) and resolves to the new version, or null when
/// there's nothing newer. Network/parsing failures throw and land in the
/// provider's [AsyncError] state — callers that only want the silent,
/// automatic-banner behavior read [AsyncValue.valueOrNull] (an error there
/// reads the same as "nothing found"); the manual "Check for updates"
/// button in Settings catches the thrown error to report it explicitly.
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  final client = HttpClient()..connectionTimeout = _checkTimeout;
  try {
    final request = await client
        .getUrl(Uri.parse(_latestReleaseUrl))
        .timeout(_checkTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'ProCheck-App');
    final response = await request.close().timeout(_checkTimeout);
    if (response.statusCode != 200) {
      throw HttpException('GitHub releases check failed: ${response.statusCode}');
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_checkTimeout);
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Malformed release response');
    }

    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) {
      throw const FormatException('Release response has no tag_name');
    }
    final latestVersion = tag.startsWith('v') ? tag.substring(1) : tag;

    final info = await PackageInfo.fromPlatform();
    if (!isNewerVersion(latestVersion, info.version)) return null;

    final notes = json['body'];
    final url = json['html_url'];
    final platform = _updatePlatform;
    final assets = platform == null
        ? null
        : pickReleaseAssets(json['assets'], platform);
    return UpdateInfo(
      assetName: assets?.name,
      assetUrl: assets?.url,
      checksumsUrl: assets?.checksums,
      version: latestVersion,
      releaseNotes: notes is String ? notes : '',
      releaseUrl: url is String
          ? url
          : 'https://github.com/jellevdberg/procheck---teranov-edition/releases/latest',
    );
  } finally {
    client.close();
  }
});

/// Compares dotted version numbers (ignoring any "-pre"/"+build" suffix) —
/// true when [remote] is strictly newer than [local].
bool isNewerVersion(String remote, String local) {
  final r = _versionParts(remote);
  final l = _versionParts(local);
  for (var i = 0; i < 3; i++) {
    final rv = i < r.length ? r[i] : 0;
    final lv = i < l.length ? l[i] : 0;
    if (rv != lv) return rv > lv;
  }
  return false;
}

List<int> _versionParts(String version) {
  final core = version.split('+').first.split('-').first;
  return core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
}

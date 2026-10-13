import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/supabase_config.dart';

const _checkTimeout = Duration(seconds: 5);

/// Where the release workflow publishes `latest.json` and the build zips: the
/// public `updates` Supabase Storage bucket. (GitHub Releases can't be read
/// anonymously while the repo is private.)
String get _manifestUrl =>
    '$supabaseUrl/storage/v1/object/public/updates/latest.json';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    this.assetUrl,
    this.sha256,
  });

  /// The new version's number (no leading "v"), e.g. "1.1.0".
  final String version;
  final String releaseNotes;

  /// This platform's build zip and its SHA-256 — null when the release has
  /// no build for this platform.
  final String? assetUrl;
  final String? sha256;
}

/// Whether the user has dismissed this session's update banner — reset on
/// every app launch, never persisted.
final updateBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Checks the update manifest once per app launch (or on manual refresh via
/// [WidgetRef.refresh]) and resolves to the new version, or null when
/// there's nothing newer. Network/parsing failures throw and land in the
/// provider's [AsyncError] state — callers that only want the silent,
/// automatic-banner behavior read [AsyncValue.valueOrNull] (an error there
/// reads the same as "nothing found"); the manual "Check for updates"
/// button in Settings catches the thrown error to report it explicitly.
final updateCheckProvider = FutureProvider<UpdateInfo?>((ref) async {
  if (supabaseUrl.isEmpty) {
    throw const FormatException('No update server configured');
  }
  final client = HttpClient()..connectionTimeout = _checkTimeout;
  try {
    final request = await client
        .getUrl(Uri.parse(_manifestUrl))
        .timeout(_checkTimeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'ProCheck-App');
    final response = await request.close().timeout(_checkTimeout);
    if (response.statusCode != 200) {
      throw HttpException('Update check failed: ${response.statusCode}');
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_checkTimeout);

    final info = await PackageInfo.fromPlatform();
    return parseUpdateManifest(
      body,
      currentVersion: info.version,
      platform: Platform.isWindows
          ? 'windows'
          : (Platform.isMacOS ? 'macos' : null),
    );
  } finally {
    client.close();
  }
});

/// Reads `latest.json` (written by `.github/workflows/release.yml`) and
/// returns the update when its version is newer than [currentVersion].
UpdateInfo? parseUpdateManifest(
  String body, {
  required String currentVersion,
  required String? platform,
}) {
  final json = jsonDecode(body);
  if (json is! Map<String, dynamic>) {
    throw const FormatException('Malformed update manifest');
  }
  final version = json['version'];
  if (version is! String || version.isEmpty) {
    throw const FormatException('Update manifest has no version');
  }
  if (!isNewerVersion(version, currentVersion)) return null;

  final build = platform == null ? null : json[platform];
  final notes = json['notes'];
  return UpdateInfo(
    version: version,
    releaseNotes: notes is String ? notes : '',
    assetUrl: build is Map && build['url'] is String
        ? build['url'] as String
        : null,
    sha256: build is Map && build['sha256'] is String
        ? (build['sha256'] as String).toLowerCase()
        : null,
  );
}

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

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../providers/update_check_provider.dart';

/// Thrown when this build can't update itself in place (Linux, a release
/// without a matching asset, an install folder the user can't write to) —
/// callers fall back to opening the release page.
class UpdateUnsupported implements Exception {
  const UpdateUnsupported(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Downloads [update]'s build for this platform, checks it against the
/// manifest's SHA-256, unpacks it, then hands off to a small detached
/// script that waits for this process to exit, swaps the install in place and
/// relaunches. Everything that can fail runs before the app closes; on
/// success this never returns (the process exits).
///
/// [onProgress] gets 0..1 while downloading, or null when the size is unknown.
Future<void> installUpdate(
  UpdateInfo update, {
  void Function(double? progress)? onProgress,
}) async {
  final assetUrl = update.assetUrl;
  final expected = update.sha256;
  if (assetUrl == null || expected == null) {
    throw const UpdateUnsupported('This release has no build for this platform.');
  }
  if (!Platform.isWindows && !Platform.isMacOS) {
    throw const UpdateUnsupported('In-app updates are not supported here.');
  }

  // The folder (Windows) or .app bundle's parent (macOS) must be writable —
  // e.g. not C:\Program Files — or the swap would silently fail after exit.
  final exe = File(Platform.resolvedExecutable);
  final installTarget = Platform.isWindows
      ? exe.parent.path
      // .../procheck.app/Contents/MacOS/procheck -> .../procheck.app
      : exe.parent.parent.parent.path;
  _assertWritable(
    Platform.isWindows ? Directory(installTarget) : Directory(installTarget).parent,
  );

  final work = await Directory.systemTemp.createTemp('procheck-update-');
  final zip = File('${work.path}${Platform.pathSeparator}update.zip');
  await _download(assetUrl, zip, onProgress);

  final actual = (await sha256.bind(zip.openRead()).first).toString();
  if (actual != expected) {
    // Not UpdateUnsupported: that falls back to opening the same zip.
    throw StateError('The downloaded update failed its checksum.');
  }

  final unpacked = '${work.path}${Platform.pathSeparator}unpacked';
  if (Platform.isWindows) {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'Expand-Archive -LiteralPath "${zip.path}" -DestinationPath "$unpacked" -Force',
    ]);
    if (r.exitCode != 0) throw UpdateUnsupported('Unpack failed: ${r.stderr}');
    final script = File('${work.path}\\apply.ps1');
    await script.writeAsString(_windowsScript);
    await Process.start('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
      '$pid',
      unpacked,
      installTarget,
      exe.path,
    ], mode: ProcessStartMode.detached);
  } else {
    final r = await Process.run('ditto', ['-x', '-k', zip.path, unpacked]);
    if (r.exitCode != 0) throw UpdateUnsupported('Unpack failed: ${r.stderr}');
    final script = File('${work.path}/apply.sh');
    await script.writeAsString(_macScript);
    await Process.start('/bin/sh', [
      script.path,
      '$pid',
      '$unpacked/procheck.app',
      installTarget,
    ], mode: ProcessStartMode.detached);
  }

  // Flush Hive's fire-and-forget writes (queued sync changes) before exiting.
  await Hive.close();
  exit(0);
}

void _assertWritable(Directory dir) {
  try {
    final probe = File('${dir.path}${Platform.pathSeparator}.procheck-update-probe');
    probe.writeAsStringSync('');
    probe.deleteSync();
  } on FileSystemException {
    throw UpdateUnsupported('No permission to update ${dir.path}.');
  }
}

Future<void> _download(
  String url,
  File dest,
  void Function(double?)? onProgress,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, 'ProCheck-App');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('Download failed: ${response.statusCode}');
    }
    final total = response.contentLength;
    var received = 0;
    final sink = dest.openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? received / total : null);
      }
    } finally {
      await sink.close();
    }
  } finally {
    client.close();
  }
}

// Waits for the app to exit, copies the new build over the install folder,
// relaunches. robocopy exit codes below 8 are success.
const _windowsScript = r'''
param([int]$ProcId, [string]$Src, [string]$Dest, [string]$Exe)
Wait-Process -Id $ProcId -Timeout 60 -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
robocopy $Src $Dest /E /R:5 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
Start-Process -FilePath $Exe
''';

const _macScript = r'''
PID_="$1"; SRC="$2"; DEST="$3"
while kill -0 "$PID_" 2>/dev/null; do sleep 0.5; done
rm -rf "$DEST" && ditto "$SRC" "$DEST" && xattr -cr "$DEST"
open "$DEST"
''';

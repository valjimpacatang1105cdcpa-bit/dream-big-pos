import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// GitHub repository that hosts manually-published releases containing the
/// APK asset. Update checks call the public GitHub Releases REST API only —
/// no authentication, no background polling, and no effect on the app's
/// offline-first core functionality if the network call fails.
const String kUpdateRepoOwner = 'valjimpacatang1105cdcpa-bit';
const String kUpdateRepoName = 'dream-big-pos';

/// Details about the latest published GitHub release relevant to in-app
/// update checks.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    this.apkDownloadUrl,
    this.apkSize,
    this.htmlUrl,
  });

  /// The release tag, e.g. `v1.1.0` or `1.1.0`.
  final String tagName;

  /// Direct download URL of the `.apk` asset attached to the release, if
  /// one was uploaded.
  final String? apkDownloadUrl;

  /// Size in bytes of the APK asset as reported by GitHub, used to verify
  /// the download.
  final int? apkSize;

  /// The release's GitHub web page, used as a fallback when no APK asset is
  /// attached yet.
  final String? htmlUrl;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final assets = (json['assets'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    String? apkUrl;
    int? apkSize;
    for (final asset in assets) {
      final name = (asset['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        apkSize = (asset['size'] as num?)?.toInt();
        break;
      }
    }
    return ReleaseInfo(
      tagName: (json['tag_name'] as String? ?? '').trim(),
      apkDownloadUrl: apkUrl,
      apkSize: apkSize,
      htmlUrl: json['html_url'] as String?,
    );
  }
}

/// Outcome of an on-demand update check. Exactly one of [release] (when
/// [hasUpdate] is true) or [errorMessage] (when the check itself failed) is
/// meaningful; both may be null when the app is already up to date.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.hasUpdate,
    this.release,
    this.errorMessage,
  });

  final bool hasUpdate;
  final ReleaseInfo? release;
  final String? errorMessage;

  bool get failed => errorMessage != null;
}

/// Strips a leading "v"/"V" and any build-metadata suffix (e.g. "+3") from a
/// version string, then splits it into numeric parts. Non-numeric or
/// missing parts are treated as 0 so comparisons never throw.
List<int> parseVersionParts(String rawVersion) {
  final cleaned = rawVersion.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final withoutBuild = cleaned.split('+').first;
  return withoutBuild
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList();
}

/// Returns true when [remoteVersion] (e.g. a GitHub release tag) is strictly
/// newer than [currentVersion] (e.g. the app's own pubspec version), using a
/// semantic-version-style numeric comparison. Safe against malformed or
/// missing segments — never throws.
bool isNewerVersion(String remoteVersion, String currentVersion) {
  final remote = parseVersionParts(remoteVersion);
  final current = parseVersionParts(currentVersion);
  final length = remote.length > current.length
      ? remote.length
      : current.length;
  for (var i = 0; i < length; i++) {
    final remotePart = i < remote.length ? remote[i] : 0;
    final currentPart = i < current.length ? current[i] : 0;
    if (remotePart != currentPart) return remotePart > currentPart;
  }
  return false;
}

/// Performs an on-demand (never automatic/background) check against the
/// GitHub Releases API for a newer published version than [currentVersion].
/// Any network failure (no internet, timeout, unexpected response) is
/// caught and reported through [UpdateCheckResult.errorMessage] instead of
/// throwing, so it can never crash or block the offline POS flow.
class UpdateChecker {
  UpdateChecker({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<UpdateCheckResult> checkForUpdate({
    required String currentVersion,
  }) async {
    final uri = Uri.https(
      'api.github.com',
      '/repos/$kUpdateRepoOwner/$kUpdateRepoName/releases/latest',
    );
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return UpdateCheckResult(
          hasUpdate: false,
          errorMessage:
              'Could not check for updates (server responded '
              '${response.statusCode}). You can keep using the app offline.',
        );
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final release = ReleaseInfo.fromJson(json);
      if (release.tagName.isEmpty) {
        return const UpdateCheckResult(
          hasUpdate: false,
          errorMessage: 'No published release was found yet.',
        );
      }
      final hasUpdate = isNewerVersion(release.tagName, currentVersion);
      return UpdateCheckResult(hasUpdate: hasUpdate, release: release);
    } catch (_) {
      return const UpdateCheckResult(
        hasUpdate: false,
        errorMessage:
            'Could not check for updates. Please verify your internet '
            'connection. The app continues to work fully offline.',
      );
    }
  }
}

/// Only https GitHub-hosted release assets may be downloaded in-app.
bool isAllowedApkUrl(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  final githubHost =
      host == 'github.com' ||
      host == 'objects.githubusercontent.com' ||
      host == 'release-assets.githubusercontent.com';
  return githubHost && uri.path.toLowerCase().endsWith('.apk');
}

/// Integer percent (0-100) for a download, or null when the total is unknown.
int? downloadPercent(int received, int? total) {
  if (total == null || total <= 0) return null;
  return (received * 100 ~/ total).clamp(0, 100);
}

enum ApkDownloadStatus { success, cancelled, failed }

class ApkDownloadResult {
  const ApkDownloadResult(this.status, {this.file, this.message});
  final ApkDownloadStatus status;
  final File? file;
  final String? message;
}

/// Cooperative cancel flag for an in-flight download.
class DownloadCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Streams a release APK to [destination]. Never throws: network, size and
/// cancel outcomes are returned as an [ApkDownloadResult].
class ApkDownloader {
  ApkDownloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<ApkDownloadResult> download({
    required String url,
    required File destination,
    int? expectedSize,
    DownloadCancelToken? cancelToken,
    void Function(int received, int? total)? onProgress,
  }) async {
    if (!isAllowedApkUrl(url)) {
      return const ApkDownloadResult(
        ApkDownloadStatus.failed,
        message: 'The update link is not a trusted GitHub release APK.',
      );
    }
    IOSink? openSink;
    try {
      final response = await _client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return ApkDownloadResult(
          ApkDownloadStatus.failed,
          message: 'Download failed (server responded ${response.statusCode}).',
        );
      }
      final total =
          response.contentLength != null && response.contentLength! > 0
          ? response.contentLength
          : expectedSize;
      if (await destination.exists()) await destination.delete();
      final sink = destination.openWrite();
      openSink = sink;
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (cancelToken?.isCancelled ?? false) {
          await sink.close();
          openSink = null;
          if (await destination.exists()) await destination.delete();
          return const ApkDownloadResult(ApkDownloadStatus.cancelled);
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      openSink = null;
      if (expectedSize != null && received != expectedSize) {
        await destination.delete();
        return const ApkDownloadResult(
          ApkDownloadStatus.failed,
          message: 'Downloaded file size did not match. Please try again.',
        );
      }
      return ApkDownloadResult(ApkDownloadStatus.success, file: destination);
    } catch (_) {
      try {
        await openSink?.close();
        if (await destination.exists()) await destination.delete();
      } catch (_) {}
      return const ApkDownloadResult(
        ApkDownloadStatus.failed,
        message:
            'Download interrupted. Check your internet connection and try '
            'again. The POS keeps working offline.',
      );
    }
  }
}

import 'dart:convert';

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
  const ReleaseInfo({required this.tagName, this.apkDownloadUrl, this.htmlUrl});

  /// The release tag, e.g. `v1.1.0` or `1.1.0`.
  final String tagName;

  /// Direct download URL of the `.apk` asset attached to the release, if
  /// one was uploaded.
  final String? apkDownloadUrl;

  /// The release's GitHub web page, used as a fallback when no APK asset is
  /// attached yet.
  final String? htmlUrl;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final assets = (json['assets'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    String? apkUrl;
    for (final asset in assets) {
      final name = (asset['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] as String?;
        break;
      }
    }
    return ReleaseInfo(
      tagName: (json['tag_name'] as String? ?? '').trim(),
      apkDownloadUrl: apkUrl,
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

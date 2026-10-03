import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_database.dart';

const backupFormatVersion = 1;
const _backupAppId = 'dream_big_pos';

/// SharedPreferences keys with this prefix are reserved for backup/sync
/// bookkeeping and are neither exported nor wiped by a restore.
const backupMetaPrefix = 'backup_';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A validated, versioned snapshot of all local data: every SQLite table plus
/// every SharedPreferences entry (accounts, stores, cashiers, fee rules,
/// GCash balances, and so on).
class BackupFile {
  const BackupFile({
    required this.formatVersion,
    required this.appVersion,
    required this.createdAt,
    required this.schemaVersion,
    required this.prefs,
    required this.tables,
    required this.checksum,
  });

  final int formatVersion;
  final String appVersion;
  final DateTime createdAt;
  final int schemaVersion;
  final Map<String, Object> prefs;
  final Map<String, List<Map<String, Object?>>> tables;

  /// SHA-256 of the data only (not the timestamp), so identical data always
  /// has an identical checksum. Used for corruption/tamper detection.
  final String checksum;

  int get productCount => tables['products']?.length ?? 0;
  int get transactionCount => tables['transactions']?.length ?? 0;
  int get storeCount => (prefs['local_stores'] as List?)?.length ?? 0;
}

String _typeTag(Object value) {
  if (value is String) return 's';
  if (value is bool) return 'b';
  if (value is int) return 'i';
  if (value is double) return 'd';
  if (value is List<String>) return 'sl';
  throw BackupException('Unsupported stored value type: ${value.runtimeType}');
}

String _computeChecksum(
  int schemaVersion,
  Map<String, Object> prefs,
  Map<String, List<Map<String, Object?>>> tables,
) {
  final canonical = jsonEncode({
    'schemaVersion': schemaVersion,
    'prefs': {
      for (final key in (prefs.keys.toList()..sort()))
        key: {'t': _typeTag(prefs[key]!), 'v': prefs[key]},
    },
    'tables': {
      for (final name in (tables.keys.toList()..sort())) name: tables[name],
    },
  });
  return sha256.convert(utf8.encode(canonical)).toString();
}

class BackupService {
  BackupService({LocalDatabase? database})
    : _database = database ?? LocalDatabase();

  final LocalDatabase _database;

  static String fileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'dream-big-pos-backup-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
  }

  Future<Map<String, Object>> _readPrefs() async {
    final preferences = await SharedPreferences.getInstance();
    final result = <String, Object>{};
    for (final key in preferences.getKeys()) {
      if (key.startsWith(backupMetaPrefix)) continue;
      final value = preferences.get(key);
      if (value == null) continue;
      result[key] = value is List ? List<String>.from(value) : value;
    }
    return result;
  }

  Future<BackupFile> createBackup({
    DateTime? now,
    String appVersion = 'unknown',
  }) async {
    final prefs = await _readPrefs();
    final tables = await _database.exportTables();
    return BackupFile(
      formatVersion: backupFormatVersion,
      appVersion: appVersion,
      createdAt: now ?? DateTime.now(),
      schemaVersion: LocalDatabase.schemaVersion,
      prefs: prefs,
      tables: tables,
      checksum: _computeChecksum(LocalDatabase.schemaVersion, prefs, tables),
    );
  }

  static Uint8List encode(BackupFile backup) {
    final json = {
      'app': _backupAppId,
      'formatVersion': backup.formatVersion,
      'appVersion': backup.appVersion,
      'createdAt': backup.createdAt.toUtc().toIso8601String(),
      'schemaVersion': backup.schemaVersion,
      'checksum': backup.checksum,
      'prefs': {
        for (final key in (backup.prefs.keys.toList()..sort()))
          key: {'t': _typeTag(backup.prefs[key]!), 'v': backup.prefs[key]},
      },
      'tables': {
        for (final name in (backup.tables.keys.toList()..sort()))
          name: backup.tables[name],
      },
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  /// Parses and fully validates backup bytes. Throws [BackupException] with a
  /// user-readable message; nothing is modified.
  static BackupFile parse(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const BackupException(
        'This file is not a valid backup (not JSON).',
      );
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != _backupAppId) {
      throw const BackupException('This is not a Dream Big POS backup file.');
    }
    final format = decoded['formatVersion'];
    if (format is! int || format < 1) {
      throw const BackupException(
        'Backup format version is missing or invalid.',
      );
    }
    if (format > backupFormatVersion) {
      throw BackupException(
        'This backup was made by a newer app version (format $format). '
        'Update the app first.',
      );
    }
    final schema = decoded['schemaVersion'];
    if (schema is! int || schema < 1) {
      throw const BackupException('Backup database version is invalid.');
    }
    if (schema > LocalDatabase.schemaVersion) {
      throw BackupException(
        'This backup uses a newer database version ($schema). Update the app '
        'first.',
      );
    }
    final createdAt = DateTime.tryParse('${decoded['createdAt']}');
    if (createdAt == null) {
      throw const BackupException('Backup date is missing or invalid.');
    }

    final rawPrefs = decoded['prefs'];
    final rawTables = decoded['tables'];
    if (rawPrefs is! Map || rawTables is! Map) {
      throw const BackupException('Backup data sections are missing.');
    }
    final prefs = <String, Object>{};
    for (final entry in rawPrefs.entries) {
      final key = entry.key as String;
      final item = entry.value;
      if (item is! Map || key.startsWith(backupMetaPrefix)) {
        throw BackupException('Invalid setting entry "$key".');
      }
      final value = item['v'];
      switch (item['t']) {
        case 's' when value is String:
        case 'b' when value is bool:
        case 'i' when value is int:
          prefs[key] = value as Object;
        case 'd' when value is num:
          prefs[key] = value.toDouble();
        case 'sl' when value is List && value.every((e) => e is String):
          prefs[key] = List<String>.from(value);
        default:
          throw BackupException('Invalid value for setting "$key".');
      }
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in rawTables.entries) {
      final name = entry.key as String;
      if (!LocalDatabase.backupTableNames.contains(name)) {
        throw BackupException('Unexpected table "$name" in backup.');
      }
      final rows = entry.value;
      if (rows is! List) throw BackupException('Table "$name" is invalid.');
      tables[name] = [
        for (final row in rows)
          if (row is Map<String, dynamic> &&
              row.values.every((v) => v == null || v is num || v is String))
            Map<String, Object?>.from(row)
          else
            throw BackupException('Table "$name" has an invalid row.'),
      ];
    }
    for (final name in LocalDatabase.backupTableNames) {
      tables.putIfAbsent(name, () => []);
    }
    final hasData = prefs.isNotEmpty || tables.values.any((r) => r.isNotEmpty);
    if (!hasData) {
      throw const BackupException('This backup contains no data.');
    }

    final checksum = _computeChecksum(schema, prefs, tables);
    if (checksum != decoded['checksum']) {
      throw const BackupException(
        'Backup is corrupted or was edited (checksum mismatch). It was not '
        'restored.',
      );
    }
    return BackupFile(
      formatVersion: format,
      appVersion: '${decoded['appVersion'] ?? 'unknown'}',
      createdAt: createdAt,
      schemaVersion: schema,
      prefs: prefs,
      tables: tables,
      checksum: checksum,
    );
  }

  Future<void> _applyPrefs(Map<String, Object> prefs) async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().toList()) {
      if (!key.startsWith(backupMetaPrefix) && !prefs.containsKey(key)) {
        await preferences.remove(key);
      }
    }
    for (final entry in prefs.entries) {
      final value = entry.value;
      if (value is String) {
        await preferences.setString(entry.key, value);
      } else if (value is bool) {
        await preferences.setBool(entry.key, value);
      } else if (value is int) {
        await preferences.setInt(entry.key, value);
      } else if (value is double) {
        await preferences.setDouble(entry.key, value);
      } else if (value is List<String>) {
        await preferences.setStringList(entry.key, value);
      }
    }
  }

  /// Replaces ALL local data with [backup]. The previous state is captured
  /// first and put back if anything fails, so a failed restore never leaves a
  /// half-restored app.
  Future<void> restore(BackupFile backup) async {
    final previousPrefs = await _readPrefs();
    final previousTables = await _database.exportTables();
    try {
      await _database.replaceAllTables(backup.tables);
      await _applyPrefs(backup.prefs);
    } catch (error) {
      try {
        await _database.replaceAllTables(previousTables);
        await _applyPrefs(previousPrefs);
      } catch (_) {}
      throw BackupException(
        'Restore failed and your existing data was kept. ($error)',
      );
    }
  }
}

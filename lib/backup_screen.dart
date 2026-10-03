import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'backup_service.dart';

/// Admin-only manual backup/restore. Works fully offline.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.service});

  final BackupService? service;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final BackupService service = widget.service ?? BackupService();
  bool busy = false;
  String? message;
  bool isError = false;

  void _show(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      busy = false;
      message = text;
      isError = error;
    });
  }

  Future<void> exportBackup() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      var version = 'unknown';
      try {
        final info = await PackageInfo.fromPlatform();
        version = '${info.version}+${info.buildNumber}';
      } catch (_) {}
      final backup = await service.createBackup(appVersion: version);
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Dream Big POS backup',
        fileName: BackupService.fileName(backup.createdAt),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: BackupService.encode(backup),
      );
      if (saved == null && !kIsWeb) {
        _show('Export cancelled. No file was saved.');
      } else {
        _show(
          kIsWeb
              ? 'Backup download started.'
              : 'Backup saved: ${backup.storeCount} store(s), '
                    '${backup.productCount} product row(s), '
                    '${backup.transactionCount} transaction(s).',
        );
      }
    } catch (e) {
      _show('Could not create the backup: $e', error: true);
    }
  }

  Future<void> restoreBackup() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a Dream Big POS backup',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      if (picked == null) {
        _show('Restore cancelled.');
        return;
      }
      if (bytes == null) {
        _show('Could not read the selected file.', error: true);
        return;
      }
      final backup = BackupService.parse(bytes);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Replace all data?'),
          content: Text(
            'Backup from ${backup.createdAt.toLocal()} '
            '(app ${backup.appVersion}):\n'
            '• ${backup.storeCount} store(s)\n'
            '• ${backup.productCount} product row(s)\n'
            '• ${backup.transactionCount} transaction(s)\n\n'
            'Restoring REPLACES everything currently on this device '
            '(accounts, stores, cashiers, products, sales, balances). This '
            'cannot be undone. Export a backup first if unsure.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Replace data'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        _show('Restore cancelled. Nothing was changed.');
        return;
      }
      await service.restore(backup);
      _show('Restore complete. Go back to the start screen to see your data.');
    } on BackupException catch (e) {
      _show(e.message, error: true);
    } catch (e) {
      _show('Restore failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup & restore')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Keep the backup file private'),
            subtitle: Text(
              'It contains ALL data on this device, including the admin '
              'account, cashier PINs, costs and profit. Store it somewhere '
              'safe.',
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: busy ? null : exportBackup,
          icon: const Icon(Icons.upload_file),
          label: const Text('Export backup file'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : restoreBackup,
          icon: const Icon(Icons.restore),
          label: const Text('Restore from backup file'),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (message != null)
          Card(
            color: isError ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
            child: ListTile(
              leading: Icon(isError ? Icons.error_outline : Icons.check_circle),
              title: Text(message!),
            ),
          ),
      ],
    ),
  );
}

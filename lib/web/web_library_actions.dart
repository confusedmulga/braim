import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../platform/file_open.dart';
import '../platform/file_saver.dart';
import '../platform/image_store.dart';
import '../services/store/library_zip.dart';
import '../services/store/web_local_library_store.dart';
import '../state/app_state.dart';

/// The browser-only library's two doors: a phone backup in, a backup out.
class WebLibraryActions {
  WebLibraryActions._();

  /// Replaces this browser's library with [zipBytes] (a phone backup) and
  /// reloads. Throws [FormatException] when it isn't a Braim backup.
  static Future<void> importZip(AppState state, Uint8List zipBytes) async {
    final store = state.store;
    if (store is! WebLocalLibraryStore) {
      throw StateError('Import is only available for a browser library.');
    }
    final bundle = LibraryZip.decode(zipBytes);
    await state.flushNow();
    await store.replaceAll(bundle);
    PaintingBinding.instance.imageCache.clear();
    await state.init();
  }

  /// The library plus every image it references, as a backup zip.
  static Future<Uint8List> exportZip(AppState state) async {
    final store = state.store;
    if (store is! WebLocalLibraryStore) {
      throw StateError('Export is only available for a browser library.');
    }
    await state.flushNow();
    final data = state.currentSnapshot();
    final wanted = {for (final p in referencedImagePaths(data)) imageKey(p)};
    final images = await store.allImages();
    images.removeWhere((k, _) => !wanted.contains(k));
    return LibraryZip.encode(data, images);
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}';
  }

  /// Picks a backup zip and imports it, asking first when this browser already
  /// holds a library. Returns whether a library was imported.
  static Future<bool> pickAndImport(BuildContext context) async {
    final t = context.t;
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final picked = await pickOneFile(extensions: const ['zip']);
    if (picked == null || !context.mounted) return false;
    if (!state.isLibraryEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.webReplaceTitle),
          content: Text(t.webReplaceBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t.webReplace)),
          ],
        ),
      );
      if (ok != true || !context.mounted) return false;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(t.webImporting),
        content: const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(6)),
          child: LinearProgressIndicator(minHeight: 6),
        ),
      ),
    ).then((_) => dialogOpen = false);
    try {
      await importZip(state, picked.bytes);
      if (dialogOpen) nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(t.webImportDone)));
      return true;
    } on FormatException {
      if (dialogOpen) nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(t.webImportFailed)));
    } catch (e) {
      if (dialogOpen) nav.pop();
      messenger.showSnackBar(
          SnackBar(content: Text(t.restoreFailed(e.toString()))));
    }
    return false;
  }

  /// Builds a backup zip and downloads it.
  static Future<void> exportAndDownload(BuildContext context) async {
    final t = context.t;
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await exportZip(state);
      await FileSaver.saveBytes(bytes, 'braim-backup-${_stamp()}.zip',
          mime: 'application/zip');
      await state.markBackedUp();
      messenger.showSnackBar(SnackBar(content: Text(t.webExportDone)));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text(t.backupFailed(e.toString()))));
    }
  }
}

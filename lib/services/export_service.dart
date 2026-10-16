import 'dart:io';
import 'dart:typed_data';

import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';

/// UI-free plumbing for writing exported app data to the public Downloads
/// folder (Android, via MediaStore) or the app documents folder (other
/// platforms). Shared by manual JSON export, manual CSV export, and the
/// silent post-workout auto-backup.
class ExportService {
  const ExportService._();

  /// Writes [content] to [fileName] and hands it to platform storage,
  /// returning a short human-readable location description. Throws on
  /// failure — callers decide how to surface that.
  ///
  /// Passing the SAME [fileName] on a later call overwrites the previous
  /// file in place (verified: MediaStore's saveFile deletes-then-recreates
  /// a matching display name in the same folder; the pre-Android-10
  /// fallback is a plain File.copy, which also overwrites). Manual exports
  /// should keep passing a fresh timestamped filename each call so they
  /// keep accumulating as separate files, same as today.
  static Future<String> exportToDownloads({
    required String fileName,
    required String content,
  }) {
    return _write(
      fileName: fileName,
      writeTempFile: (file) => file.writeAsString(content),
    );
  }

  /// Binary counterpart of [exportToDownloads], for formats that aren't text
  /// (the PDF report). Same destination, same overwrite contract.
  static Future<String> exportBytesToDownloads({
    required String fileName,
    required Uint8List bytes,
  }) {
    return _write(
      fileName: fileName,
      writeTempFile: (file) => file.writeAsBytes(bytes),
    );
  }

  static Future<String> _write({
    required String fileName,
    required Future<void> Function(File file) writeTempFile,
  }) async {
    if (Platform.isAndroid) {
      // MediaStore takes a path, not bytes, so everything lands in the cache
      // directory first and is handed over from there.
      final tempDirectory = await getTemporaryDirectory();
      final tempFile = File('${tempDirectory.path}${Platform.pathSeparator}$fileName');
      await writeTempFile(tempFile);

      await MediaStore.ensureInitialized();
      MediaStore.appFolder = 'GymTracker';
      final saveInfo = await MediaStore().saveFile(
        tempFilePath: tempFile.path,
        dirType: DirType.download,
        dirName: DirName.download,
      );

      if (saveInfo == null) {
        throw Exception('Could not save "$fileName" to Downloads');
      }
      return 'Downloads/${MediaStore.appFolder}/${saveInfo.name}';
    } else {
      final appDirectory = await getApplicationDocumentsDirectory();
      final exportFile = File('${appDirectory.path}${Platform.pathSeparator}$fileName');
      await writeTempFile(exportFile);
      return exportFile.path;
    }
  }
}

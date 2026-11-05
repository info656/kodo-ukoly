import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zest/app/data/db.dart';
import 'package:zest/app/constants/app_constants.dart';
import 'package:zest/app/utils/show_snack_bar.dart';
import 'package:zest/main.dart';

class IsarController {
  static const _platform = MethodChannel('directory_picker');
  static const String _backupPrefix = 'backup_zest_db_';
  static const String _backupExtension = '.isar';
  static const String _compressedExtension = '.gz';

  // ==================== Database ====================

  static Future<Isar> openDB() async {
    if (Isar.instanceNames.isEmpty) {
      final dir = await getApplicationSupportDirectory();
      final isarInstance = await Isar.open(
        [TasksSchema, TodosSchema, SettingsSchema],
        directory: dir.path,
        inspector: true,
      );

      isar = isarInstance;

      await _migrateToStatusField(isarInstance);

      return isarInstance;
    }

    return Future.value(Isar.getInstance());
  }

  static Future<void> _migrateToStatusField(Isar isar) async {
    try {
      final todos = await isar.todos.where().findAll();

      final needsMigration = todos.any(
        (todo) => todo.done == true && todo.status == TodoStatus.active,
      );

      if (!needsMigration) {
        debugPrint('Migration: No migration needed');
        return;
      }

      int migratedCount = 0;
      await isar.writeTxn(() async {
        for (final todo in todos) {
          if (todo.done == true && todo.status == TodoStatus.active) {
            todo.status = TodoStatus.done;
            todo.todoCompletionTime ??= todo.createdTime;
            await isar.todos.put(todo);
            migratedCount++;
          }
        }
      });

      debugPrint(
        'Migration completed: Updated $migratedCount of ${todos.length} todos from done field to status field',
      );
    } catch (e) {
      debugPrint('Migration error: $e');
    }
  }

  // ==================== Backup ====================

  Future<void> createBackup() async {
    try {
      final backupDir = await _pickDirectory();
      if (backupDir == null) {
        return;
      }

      final allowedPath = await _getAllowedPath(backupDir);

      if (allowedPath == null) {
        showSnackBar('errorPath'.tr, isInfo: true);
        return;
      }
      _showLoadingDialog('creatingBackup'.tr);

      final backupFileName = _generateBackupFileName();
      final backupFile = File('$allowedPath/$backupFileName');

      await _prepareBackupFile(backupFile);
      await isar.copyToFile(backupFile.path);

      final compressedFileName = '$backupFileName$_compressedExtension';
      final compressedFile = File('$allowedPath/$compressedFileName');

      await _compressFile(backupFile, compressedFile);
      await backupFile.delete();

      if (Platform.isAndroid) {
        await _saveBackupAndroid(
          backupDir: backupDir,
          compressedFile: compressedFile,
          fileName: compressedFileName,
        );
      } else {
        _hideLoadingDialog();
        showSnackBar('successBackup'.tr);
      }
    } catch (e, stackTrace) {
      _hideLoadingDialog();
      debugPrint('Backup error: $e\n$stackTrace');
      showSnackBar('error'.tr, isError: true);
    }
  }

  Future<void> _saveBackupAndroid({
    required String backupDir,
    required File compressedFile,
    required String fileName,
  }) async {
    try {
      final backupData = await compressedFile.readAsBytes();

      final success = await _platform.invokeMethod<bool>('writeFile', {
        'directoryUri': backupDir,
        'fileName': fileName,
        'fileContent': backupData,
      });

      await compressedFile.delete();
      _hideLoadingDialog();

      if (success == true) {
        showSnackBar('successBackup'.tr);
      } else {
        showSnackBar('error'.tr, isError: true);
      }
    } catch (e) {
      await compressedFile.delete();
      _hideLoadingDialog();
      debugPrint('Android backup save error: $e');
      showSnackBar('error'.tr, isError: true);
    }
  }

  // ==================== Restore ====================

  Future<void> restoreDB() async {
    showSnackBar(
      "Úkoly se načítají ze serveru Kodo; místní import není zapnutý.",
      isInfo: true,
    );
  }

  // ==================== Helpers ====================

  String _generateBackupFileName() {
    final timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '$_backupPrefix$timeStamp$_backupExtension';
  }

  Future<void> _prepareBackupFile(File backupFile) async {
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
  }

  Future<void> _compressFile(File source, File destination) async {
    final bytes = await source.readAsBytes();
    final encoder = GZipEncoder();
    final compressedData = encoder.encode(bytes);

    await destination.writeAsBytes(compressedData);
  }

  // ==================== Directory Picker ====================

  Future<String?> pickAutoBackupDirectory() async {
    return await _pickDirectory();
  }

  Future<String?> _pickDirectory() async {
    if (Platform.isAndroid) {
      return await _pickDirectoryAndroid();
    } else if (Platform.isIOS) {
      return await _getDirectoryPath();
    }
    return null;
  }

  Future<String?> _pickDirectoryAndroid() async {
    try {
      final String? uri = await _platform.invokeMethod('pickDirectory');
      return uri;
    } on PlatformException catch (e) {
      debugPrint('Error picking directory: $e');
      return null;
    }
  }

  Future<String> _getDirectoryPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String?> _getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download';
    } else if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    }
    return null;
  }

  Future<String?> _getAllowedPath(String? backupDir) async {
    if (Platform.isAndroid) {
      return await _getDownloadsDirectory();
    }
    return backupDir;
  }

  // ==================== Loading Dialog ====================

  void _showLoadingDialog(String message) {
    final context = Get.context;
    if (context == null) return;

    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: AppConstants.maxDialogWidth,
            ),
            child: Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppConstants.borderRadiusXXLarge,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spacingXXL),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: colorScheme.primary,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: AppConstants.spacingXL),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _hideLoadingDialog() {
    final context = Get.context;
    if (context != null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

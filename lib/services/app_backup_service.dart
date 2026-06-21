import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../data/app_database.dart';

class AppBackupService {
  const AppBackupService();

  static const String backupFormat = 'huiyunxuan.backup.v1';
  static const int backupSchemaVersion = 1;

  Future<BackupExportResult?> exportBackup() async {
    final database = AppDatabase.instance;
    final tableData = await database.exportBackupTables();
    final backup = <String, Object?>{
      'format': backupFormat,
      'schemaVersion': backupSchemaVersion,
      'databaseVersion': await database.currentDatabaseVersion(),
      'createdAt': DateTime.now().toIso8601String(),
      'tables': tableData,
    };

    final encoded = const JsonEncoder.withIndent('  ').convert(backup);
    final bytes = Uint8List.fromList(utf8.encode(encoded));
    final fileName = _backupFileName();

    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存绘云轩备份',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['hyxbak'],
      bytes: bytes,
    );

    if (path == null) {
      return null;
    }

    return BackupExportResult(
      fileName: fileName,
      path: path,
      poemCount: tableData['poem_elements']?.length ?? 0,
      collectionCount: tableData['poem_collections']?.length ?? 0,
    );
  }

  Future<BackupImportResult?> pickAndImportBackup() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择绘云轩备份',
      type: FileType.any,
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      throw const BackupImportException('无法读取所选文件。');
    }

    final source = _decodeBackupBytes(bytes);
    if (source.trim().isEmpty) {
      throw const BackupImportException('备份文件为空，未执行导入。');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const BackupImportException('所选文件不是有效的绘云轩备份。');
    }
    if (decoded is! Map) {
      throw const BackupImportException('这不是有效的绘云轩备份文件。');
    }

    if (decoded['format'] != backupFormat) {
      throw const BackupImportException('备份格式不匹配，未执行导入。');
    }

    final tables = decoded['tables'];
    if (tables is! Map) {
      throw const BackupImportException('备份文件缺少数据表内容。');
    }

    final databaseVersion = decoded['databaseVersion'];
    final currentVersion = await AppDatabase.instance.currentDatabaseVersion();
    if (databaseVersion is int && databaseVersion > currentVersion) {
      throw BackupImportException(
        '备份来自更新版本的数据库，请先升级当前 App。备份版本：$databaseVersion，当前版本：$currentVersion。',
      );
    }

    final normalizedTables = <String, List<Map<String, Object?>>>{};
    for (final tableName in AppDatabase.backupTableNames) {
      final rawRows = tables[tableName];
      if (rawRows == null) {
        normalizedTables[tableName] = const <Map<String, Object?>>[];
        continue;
      }
      if (rawRows is! List) {
        throw BackupImportException('备份中的 $tableName 数据格式不正确。');
      }
      normalizedTables[tableName] = [
        for (final row in rawRows)
          if (row is Map)
            Map<String, Object?>.from(
              row.map((key, value) => MapEntry(key.toString(), value)),
            )
          else
            throw BackupImportException('备份中的 $tableName 存在无法识别的记录。'),
      ];
    }

    await AppDatabase.instance.importBackupTables(normalizedTables);

    return BackupImportResult(
      fileName: file.name,
      poemCount: normalizedTables['poem_elements']?.length ?? 0,
      collectionCount: normalizedTables['poem_collections']?.length ?? 0,
    );
  }

  String _decodeBackupBytes(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }
    return text;
  }

  String _backupFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = [
      now.year.toString().padLeft(4, '0'),
      two(now.month),
      two(now.day),
      '_',
      two(now.hour),
      two(now.minute),
      two(now.second),
    ].join();
    return 'huiyunxuan_backup_$stamp.hyxbak';
  }
}

class BackupExportResult {
  const BackupExportResult({
    required this.fileName,
    required this.path,
    required this.poemCount,
    required this.collectionCount,
  });

  final String fileName;
  final String path;
  final int poemCount;
  final int collectionCount;
}

class BackupImportResult {
  const BackupImportResult({
    required this.fileName,
    required this.poemCount,
    required this.collectionCount,
  });

  final String fileName;
  final int poemCount;
  final int collectionCount;
}

class BackupImportException implements Exception {
  const BackupImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

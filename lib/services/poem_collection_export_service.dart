import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../data/app_database.dart';
import '../models/poem.dart';
import '../models/poem_collection.dart';

class PoemCollectionExportService {
  const PoemCollectionExportService();

  Future<PoemCollectionExportResult?> exportCollection(
    PoemCollection collection,
  ) async {
    final collectionId = collection.id;
    if (collectionId == null) {
      throw const FormatException('无法导出尚未保存的诗词库。');
    }

    final poems = await AppDatabase.instance.getPoems(collectionId);
    final exportData = <String, Object?>{
      'format': 'huiyunxuan.collection.v1',
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'collection': {
        'name': collection.name,
        'description': collection.description,
      },
      'poems': [for (final poem in poems) _poemToJson(poem)],
    };

    final text = const JsonEncoder.withIndent('  ').convert(exportData);
    final fileName = _exportFileName(collection.name);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出诗词库',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: Uint8List.fromList(utf8.encode(text)),
    );

    if (path == null) {
      return null;
    }

    return PoemCollectionExportResult(
      fileName: fileName,
      path: path,
      poemCount: poems.length,
    );
  }

  Map<String, Object?> _poemToJson(Poem poem) {
    return {
      'title': poem.title,
      'author': poem.author,
      'dynasty': poem.dynasty,
      'preface': poem.preface,
      'content': poem.content,
      'remark': poem.remark,
      'translation': poem.translation,
      'annotation': poem.annotation,
      'learning_note': poem.learningNote,
      'appreciation': poem.appreciation,
      'prosody': {
        'supported': poem.prosodySupported,
        'enabled': poem.prosodyEnabled,
        'system': poem.prosodySystem,
        'form': poem.prosodyForm,
        'rhyme_book': poem.prosodyRhymeBook,
        'note': poem.prosodyNote,
        'overrides': poem.prosodyOverridesJson,
        'verified_at': poem.prosodyVerifiedAt?.toIso8601String(),
        'verified_by': poem.prosodyVerifiedBy,
      },
    };
  }

  String _exportFileName(String collectionName) {
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
    final safeName = collectionName
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    final name = safeName.isEmpty ? 'collection' : safeName;
    return 'huiyunxuan_collection_${name}_$stamp.json';
  }
}

class PoemCollectionExportResult {
  const PoemCollectionExportResult({
    required this.fileName,
    required this.path,
    required this.poemCount,
  });

  final String fileName;
  final String path;
  final int poemCount;
}

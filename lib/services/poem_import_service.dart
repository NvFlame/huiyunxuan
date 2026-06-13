import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

const poemImportFileExtensions = ['json', 'jsonl', 'txt'];

class ImportedPoemDraft {
  const ImportedPoemDraft({
    required this.title,
    required this.author,
    required this.dynasty,
    required this.preface,
    required this.content,
    required this.remark,
    required this.translation,
    required this.annotation,
    required this.learningNote,
    required this.appreciation,
  });

  final String title;
  final String author;
  final String dynasty;
  final String preface;
  final String content;
  final String remark;
  final String translation;
  final String annotation;
  final String learningNote;
  final String appreciation;

  bool get isValid => title.trim().isNotEmpty && content.trim().isNotEmpty;

  factory ImportedPoemDraft.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('诗词条目必须是 JSON 对象');
    }

    final map = value.cast<Object?, Object?>();
    return ImportedPoemDraft(
      title: _readString(map, ['title', '标题']),
      author: _readString(map, ['author', '作者']),
      dynasty: _readString(map, ['dynasty', '朝代']),
      preface: _readString(map, ['preface', '序', '小序']),
      content: _readString(map, ['content', '内容', '正文']),
      remark: _readString(map, ['remark', '备注', '别名']),
      translation: _readString(map, ['translation', '译文']),
      annotation: _readString(map, ['annotation', '注释']),
      learningNote: _readString(
        map,
        ['learning_note', 'learningNote', '学习笔记'],
      ),
      appreciation: _readString(map, ['appreciation', '赏析']),
    );
  }
}

class ImportedCollectionDraft {
  const ImportedCollectionDraft({
    required this.name,
    required this.description,
    required this.poems,
  });

  final String name;
  final String description;
  final List<ImportedPoemDraft> poems;
}

ImportedCollectionDraft parsePoemCollectionImport(
  String text, {
  String fallbackName = '',
  String fallbackDescription = '',
}) {
  final value = _decodeImportText(text);
  var name = fallbackName.trim();
  var description = fallbackDescription.trim();
  late final List<Object?> poemValues;

  if (value is Map) {
    final map = value.cast<Object?, Object?>();
    final collectionValue = _readValue(map, ['collection', 'database', '诗词库']);
    final collectionMap = collectionValue is Map
        ? collectionValue.cast<Object?, Object?>()
        : map;
    name = _firstNonEmpty([
      _readString(
        collectionMap,
        ['name', 'collection_name', 'database_name', '数据库名称'],
      ),
      name,
    ]);
    description = _firstNonEmpty([
      _readString(collectionMap, ['description', '说明']),
      description,
    ]);
    final poemsValue = _readValue(map, ['poems', '诗词', 'items', 'data']) ??
        _readValue(collectionMap, ['poems', '诗词', 'items', 'data']);
    if (poemsValue is List) {
      poemValues = poemsValue.cast<Object?>();
    } else if (_looksLikePoemMap(map)) {
      poemValues = [value];
    } else {
      throw const FormatException('诗词库 JSON 中没有找到 poems 数组');
    }
  } else if (value is List) {
    poemValues = value.cast<Object?>();
  } else {
    throw const FormatException('导入内容必须是 JSON 对象、数组或 JSONL');
  }

  final poems = poemValues.map(ImportedPoemDraft.fromJson).toList();
  final invalidIndex = poems.indexWhere((poem) => !poem.isValid);
  if (invalidIndex >= 0) {
    throw FormatException('第 ${invalidIndex + 1} 首诗缺少标题或内容');
  }
  if (poems.isEmpty) {
    throw const FormatException('没有可导入的诗词');
  }

  return ImportedCollectionDraft(
    name: name,
    description: description,
    poems: poems,
  );
}

ImportedPoemDraft parseSinglePoemImport(String text) {
  final value = _decodeImportText(text);
  Object? poemValue = value;

  if (value is Map) {
    final map = value.cast<Object?, Object?>();
    final poemsValue = _readValue(map, ['poems', '诗词', 'items', 'data']);
    if (poemsValue is List && poemsValue.isNotEmpty) {
      poemValue = poemsValue.first;
    }
  } else if (value is List) {
    if (value.isEmpty) {
      throw const FormatException('没有可导入的诗词');
    }
    poemValue = value.first;
  }

  final poem = ImportedPoemDraft.fromJson(poemValue);
  if (!poem.isValid) {
    throw const FormatException('导入诗词缺少标题或内容');
  }
  return poem;
}

Future<String?> pickPoemImportFileText() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: poemImportFileExtensions,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) {
    return null;
  }

  final file = result.files.single;
  final bytes = file.bytes;
  if (bytes != null) {
    return _removeUtf8Bom(utf8.decode(bytes, allowMalformed: true));
  }

  final path = file.path;
  if (path == null || path.trim().isEmpty) {
    throw const FormatException('无法读取文件内容，请改用粘贴文本导入');
  }
  return _removeUtf8Bom(await File(path).readAsString());
}

Object? _decodeImportText(String text) {
  final source = text.trim();
  if (source.isEmpty) {
    throw const FormatException('请粘贴 JSON 或 JSONL 内容');
  }

  try {
    return jsonDecode(source);
  } on FormatException {
    final lines = source
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length <= 1) {
      rethrow;
    }
    return [for (final line in lines) jsonDecode(line)];
  }
}

String _removeUtf8Bom(String text) {
  return text.replaceFirst('\ufeff', '');
}

Object? _readValue(Map<Object?, Object?> map, List<String> keys) {
  for (final key in keys) {
    if (map.containsKey(key)) {
      return map[key];
    }
  }
  return null;
}

String _readString(Map<Object?, Object?> map, List<String> keys) {
  final value = _readValue(map, keys);
  if (value == null) {
    return '';
  }
  if (value is List) {
    return value.map((item) => item.toString().trim()).join('\n').trim();
  }
  return value.toString().trim();
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    if (value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

bool _looksLikePoemMap(Map<Object?, Object?> map) {
  return _readString(map, ['title', '标题']).isNotEmpty ||
      _readString(map, ['content', '内容', '正文']).isNotEmpty;
}

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/api_config.dart';
import '../models/poem.dart';
import '../models/poem_collection.dart';
import '../services/poem_fingerprint_service.dart';
import '../services/prosody_service.dart';

class JinshiAchievementEntry {
  const JinshiAchievementEntry({
    required this.poem,
    required this.firstJinshiAt,
  });

  final Poem poem;
  final DateTime firstJinshiAt;
}

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static const int schemaVersion = 19;
  static const List<String> backupTableNames = [
    'poem_collections',
    'poem_elements',
    'collection_poems',
    'api_configs',
    'poem_agent_messages',
    'learning_progress',
    'training_progress',
    'training_achievements',
  ];

  static const List<String> _backupDeleteOrder = [
    'poem_agent_messages',
    'learning_progress',
    'training_progress',
    'training_achievements',
    'collection_poems',
    'api_configs',
    'poem_collections',
    'poem_elements',
  ];

  static const List<String> _backupInsertOrder = [
    'poem_collections',
    'poem_elements',
    'collection_poems',
    'api_configs',
    'poem_agent_messages',
    'learning_progress',
    'training_progress',
    'training_achievements',
  ];

  static const Map<String, String> _backupTableOrderBy = {
    'poem_collections': 'id ASC',
    'poem_elements': 'id ASC',
    'collection_poems': 'collection_id ASC, sort_order ASC, created_at ASC, poem_id ASC',
    'api_configs': 'id ASC',
    'poem_agent_messages': 'id ASC',
    'learning_progress': 'collection_id ASC',
    'training_progress': 'collection_id ASC',
    'training_achievements': 'poem_id ASC',
  };

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final opened = await _openDatabase();
    _database = opened;
    return opened;
  }

  Future<Database> _openDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, 'huiyunxuan.db');

    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE poem_collections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  is_favorites INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

        await _createPoemElementTables(db);
        await _createApiConfigTable(db);
        await _createPoemAgentMessageTable(db);
        await _createLearningProgressTable(db);
        await _createTrainingTables(db);
        await _ensureBuiltInCollections(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE poems ADD COLUMN annotation TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE poems ADD COLUMN appreciation TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 3) {
          await _migratePoemsToElements(db);
        }
        if (oldVersion < 4) {
          await _createApiConfigTable(db);
        }
        if (oldVersion >= 3 && oldVersion < 5) {
          await db.execute(
            "ALTER TABLE poem_elements ADD COLUMN translation TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion >= 4 && oldVersion < 6) {
          await db.execute(
            "ALTER TABLE api_configs ADD COLUMN search_provider TEXT NOT NULL DEFAULT '${ApiConfig.searchProviderNone}'",
          );
          await db.execute(
            "ALTER TABLE api_configs ADD COLUMN search_api_key TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            'ALTER TABLE api_configs ADD COLUMN search_max_results INTEGER NOT NULL DEFAULT 5',
          );
          await db.execute(
            'ALTER TABLE api_configs ADD COLUMN search_include_raw_content INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion >= 4 && oldVersion < 7) {
          await db.execute(
            "ALTER TABLE api_configs ADD COLUMN tavily_search_api_key TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE api_configs ADD COLUMN bocha_search_api_key TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            '''
UPDATE api_configs
SET tavily_search_api_key = search_api_key
WHERE search_provider = '${ApiConfig.searchProviderTavily}'
AND search_api_key != ''
''',
          );
          await db.execute(
            '''
UPDATE api_configs
SET bocha_search_api_key = search_api_key
WHERE search_provider = '${ApiConfig.searchProviderBocha}'
AND search_api_key != ''
            ''',
          );
        }
        if (oldVersion < 8) {
          await _createPoemAgentMessageTable(db);
        }
        if (oldVersion >= 3 && oldVersion < 9) {
          await db.execute(
            "ALTER TABLE poem_elements ADD COLUMN preface TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 9) {
          await _createLearningProgressTable(db);
        }
        if (oldVersion >= 3 && oldVersion < 10) {
          await db.execute(
            "ALTER TABLE poem_elements ADD COLUMN learning_note TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 11) {
          await db.execute(
            'ALTER TABLE poem_collections ADD COLUMN is_favorites INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 12) {
          await _createTrainingTables(db);
        }
        if (oldVersion >= 3 && oldVersion < 13) {
          await _addProsodyColumns(db);
        }
        if (oldVersion >= 3 && oldVersion < 15) {
          await _addProsodyFoundationColumns(db);
        }
        if (oldVersion < 13) {
          await _backfillProsodyMetadata(db);
        }
        if (oldVersion < 14) {
          await _normalizeProsodyMetadata(db);
        }
        if (oldVersion < 15) {
          await _backfillProsodyMetadata(db);
        }
        if (oldVersion < 16) {
          await _ensureCollectionPoemSortOrderColumn(db);
        }
        if (oldVersion < 17) {
          await _ensureBuiltInCollections(db);
        }
        if (oldVersion < 18) {
          await _normalizeProsodyMetadata(db);
        }
        if (oldVersion >= 3 && oldVersion < 19) {
          await _addPoemFingerprintColumns(db);
        }
        if (oldVersion < 19) {
          await _backfillPoemFingerprints(db);
        }
      },
    );
  }

  Future<void> _createPoemAgentMessageTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS poem_agent_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scope_key TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_poem_agent_messages_scope '
      'ON poem_agent_messages(scope_key, created_at, id)',
    );
  }

  Future<void> _createApiConfigTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE api_configs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  api_spec TEXT NOT NULL DEFAULT '${ApiConfig.openAiSpec}',
  api_key TEXT NOT NULL DEFAULT '',
  base_url TEXT NOT NULL DEFAULT '',
  chat_model TEXT NOT NULL DEFAULT '',
  embedding_model TEXT NOT NULL DEFAULT '',
  search_provider TEXT NOT NULL DEFAULT '${ApiConfig.searchProviderNone}',
  search_api_key TEXT NOT NULL DEFAULT '',
  tavily_search_api_key TEXT NOT NULL DEFAULT '',
  bocha_search_api_key TEXT NOT NULL DEFAULT '',
  search_max_results INTEGER NOT NULL DEFAULT 5,
  search_include_raw_content INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute(
      'CREATE INDEX idx_api_configs_is_active ON api_configs(is_active)',
    );
    await db.execute('CREATE INDEX idx_api_configs_name ON api_configs(name)');
  }

  Future<void> _createPoemElementTables(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE poem_elements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  identity TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  dynasty TEXT NOT NULL DEFAULT '',
  preface TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL,
  remark TEXT NOT NULL DEFAULT '',
  translation TEXT NOT NULL DEFAULT '',
  annotation TEXT NOT NULL DEFAULT '',
  learning_note TEXT NOT NULL DEFAULT '',
  appreciation TEXT NOT NULL DEFAULT '',
  prosody_enabled INTEGER NOT NULL DEFAULT 0,
  prosody_supported INTEGER NOT NULL DEFAULT 0,
  prosody_system TEXT NOT NULL DEFAULT '${Poem.prosodySystemUnknown}',
  prosody_form TEXT NOT NULL DEFAULT '',
  prosody_rhyme_book TEXT NOT NULL DEFAULT '',
  prosody_note TEXT NOT NULL DEFAULT '',
  prosody_overrides_json TEXT NOT NULL DEFAULT '',
  prosody_verified_at INTEGER,
  prosody_verified_by TEXT NOT NULL DEFAULT '',
  exact_content_hash TEXT NOT NULL DEFAULT '',
  work_fingerprint TEXT NOT NULL DEFAULT '',
  content_shape_hash TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE collection_poems (
  collection_id INTEGER NOT NULL,
  poem_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (collection_id, poem_id),
  FOREIGN KEY (collection_id)
    REFERENCES poem_collections (id)
    ON DELETE CASCADE,
  FOREIGN KEY (poem_id)
    REFERENCES poem_elements (id)
    ON DELETE CASCADE
)
''');

    await db.execute(
      'CREATE INDEX idx_collection_poems_collection_id '
      'ON collection_poems(collection_id)',
    );
    await db.execute(
      'CREATE INDEX idx_collection_poems_poem_id '
      'ON collection_poems(poem_id)',
    );
    await db.execute(
      'CREATE INDEX idx_poem_elements_title ON poem_elements(title)',
    );
    await db.execute(
      'CREATE INDEX idx_poem_elements_author ON poem_elements(author)',
    );
    await _createPoemFingerprintIndexes(db);
  }

  Future<void> _createPoemFingerprintIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_poem_elements_exact_content_hash '
      'ON poem_elements(exact_content_hash)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_poem_elements_work_fingerprint '
      'ON poem_elements(work_fingerprint)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_poem_elements_content_shape_hash '
      'ON poem_elements(content_shape_hash)',
    );
  }

  Future<void> _addPoemFingerprintColumns(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE poem_elements ADD COLUMN exact_content_hash TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE poem_elements ADD COLUMN work_fingerprint TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE poem_elements ADD COLUMN content_shape_hash TEXT NOT NULL DEFAULT ''",
    );
    await _createPoemFingerprintIndexes(db);
  }

  Future<void> _ensureBuiltInCollections(DatabaseExecutor db) async {
    await _ensureTangPoemsCollection(db);
    await _ensureFavoritesCollection(db);
  }

  Future<void> _ensureFavoritesCollection(DatabaseExecutor db) async {
    final favoriteRows = await db.query(
      'poem_collections',
      columns: ['id'],
      where: 'is_favorites = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (favoriteRows.isNotEmpty) {
      return;
    }

    final namedRows = await db.query(
      'poem_collections',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: ['收藏夹'],
      limit: 1,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (namedRows.isNotEmpty) {
      final id = namedRows.first['id'];
      if (id is int) {
        await db.update(
          'poem_collections',
          {
            'is_favorites': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return;
    }

    await db.insert('poem_collections', {
      'name': '收藏夹',
      'description': '收藏的诗词',
      'is_favorites': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> _ensureTangPoemsCollection(DatabaseExecutor db) async {
    final existingRows = await db.query(
      'poem_collections',
      columns: ['id'],
      where: 'name = ?',
      whereArgs: ['唐诗三百首'],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      return;
    }

    final seedPoems = await _loadBuiltInTangPoems();
    if (seedPoems.isEmpty) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final collectionId = await db.insert('poem_collections', {
      'name': '唐诗三百首',
      'description': '蘅塘退士',
      'is_favorites': 0,
      'created_at': now,
      'updated_at': now,
    });

    var sortOrder = 0;
    for (final data in seedPoems) {
      await _insertSeedPoem(db, collectionId, data, sortOrder);
      sortOrder += 1;
    }
  }

  Future<List<Map<String, Object?>>> _loadBuiltInTangPoems() async {
    try {
      final raw = await rootBundle.loadString('assets/data/tang_poems_300.json');
      final decoded = jsonDecode(raw);
      final source = decoded is Map
          ? decoded['poems'] ?? decoded['items'] ?? decoded['data']
          : decoded;
      if (source is! List) {
        return const <Map<String, Object?>>[];
      }
      return [
        for (final item in source)
          if (item is Map)
            item.map((key, value) => MapEntry(key.toString(), value)),
      ];
    } catch (_) {
      return const <Map<String, Object?>>[];
    }
  }

  Future<void> _insertSeedPoem(
    DatabaseExecutor db,
    int collectionId,
    Map<String, Object?> data,
    int sortOrder,
  ) async {
    final now = DateTime.now();
    final inferredProsody = inferProsodyMetadata(
      title: _seedString(data['title']),
      dynasty: _seedString(data['dynasty']),
      content: _seedString(data['content']),
      remark: _seedString(data['remark']),
    );
    final prosodySystem = _seedProsodyString(data, ['system']);
    final prosodyForm = _seedProsodyString(data, ['form', 'prosody_form']);
    final prosodyRhymeBook = _seedProsodyString(
      data,
      ['rhyme_book', 'prosody_rhyme_book'],
    );
    final prosodyNote = _seedProsodyString(data, ['note', 'prosody_note']);
    final prosodyOverrides = _seedProsodyString(
      data,
      ['overrides', 'prosody_overrides_json'],
    );
    final prosodyVerifiedBy = _seedProsodyString(
      data,
      ['verified_by', 'prosody_verified_by'],
    );
    final prosodyVerifiedAt = _seedDate(
      _seedProsodyValue(data, 'verified_at') ??
          _seedProsodyValue(data, 'prosody_verified_at'),
    );
    final hasProsodyMetadata = prosodySystem.isNotEmpty ||
        prosodyForm.isNotEmpty ||
        prosodyRhymeBook.isNotEmpty ||
        prosodyOverrides.isNotEmpty ||
        prosodyVerifiedAt != null ||
        prosodyVerifiedBy.isNotEmpty;
    final resolvedSystem =
        prosodySystem.isEmpty ? inferredProsody.system : prosodySystem;
    final resolvedSupported = _seedBool(
          _seedProsodyValue(data, 'supported') ??
              _seedProsodyValue(data, 'prosody_supported'),
        ) ??
        (hasProsodyMetadata &&
                resolvedSystem != Poem.prosodySystemUnknown &&
                resolvedSystem != Poem.prosodySystemUnsupported
            ? true
            : inferredProsody.supported);
    final resolvedEnabled = resolvedSupported &&
        (_seedBool(
              _seedProsodyValue(data, 'enabled') ??
                  _seedProsodyValue(data, 'prosody_enabled'),
            ) ??
            (hasProsodyMetadata ? true : inferredProsody.enabled));
    final fingerprint = buildPoemFingerprint(
      author: _seedString(data['author']),
      content: _seedString(data['content']),
    );

    final poem = Poem(
      collectionId: collectionId,
      identity: _generatePoemIdentity(),
      title: _seedString(data['title']),
      author: _seedString(data['author']),
      dynasty: _seedString(data['dynasty']),
      preface: _seedString(data['preface']),
      content: _seedString(data['content']),
      remark: _seedString(data['remark']),
      translation: _seedString(data['translation']),
      annotation: _seedString(data['annotation']),
      learningNote: _seedString(
        data['learning_note'] ?? data['learningNote'],
      ),
      appreciation: _seedString(data['appreciation']),
      prosodySupported: resolvedSupported,
      prosodyEnabled: resolvedEnabled,
      prosodySystem: resolvedSystem,
      prosodyForm: prosodyForm.isEmpty ? inferredProsody.form : prosodyForm,
      prosodyRhymeBook: prosodyRhymeBook.isEmpty
          ? inferredProsody.rhymeBook
          : prosodyRhymeBook,
      prosodyNote: prosodyNote.isEmpty ? inferredProsody.note : prosodyNote,
      prosodyOverridesJson: prosodyOverrides,
      prosodyVerifiedAt: prosodyVerifiedAt,
      prosodyVerifiedBy: prosodyVerifiedBy,
      exactContentHash: fingerprint.exactContentHash,
      workFingerprint: fingerprint.workFingerprint,
      contentShapeHash: fingerprint.contentShapeHash,
      createdAt: now,
      updatedAt: now,
    );
    final poemId = await db.insert('poem_elements', poem.toElementMap());
    await db.insert('collection_poems', {
      'collection_id': collectionId,
      'poem_id': poemId,
      'created_at': now.millisecondsSinceEpoch,
      'sort_order': sortOrder,
    });
  }

  String _seedString(Object? value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  String _seedProsodyString(
    Map<String, Object?> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _seedProsodyValue(data, key);
      final text = _seedString(value);
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  Object? _seedProsodyValue(Map<String, Object?> data, String key) {
    final prosody = data['prosody'];
    if (prosody is Map) {
      return prosody[key];
    }
    return data[key];
  }

  bool? _seedBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is int) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return null;
  }

  DateTime? _seedDate(Object? value) {
    if (value is int) {
      if (value <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) {
        return null;
      }
      return DateTime.tryParse(text);
    }
    return null;
  }

  Future<void> _createLearningProgressTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS learning_progress (
  collection_id INTEGER PRIMARY KEY,
  poem_id INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (collection_id)
    REFERENCES poem_collections (id)
    ON DELETE CASCADE,
  FOREIGN KEY (poem_id)
    REFERENCES poem_elements (id)
    ON DELETE CASCADE
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_learning_progress_updated_at '
      'ON learning_progress(updated_at)',
    );
  }

  Future<void> _addProsodyColumns(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE poem_elements ADD COLUMN prosody_enabled INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      "ALTER TABLE poem_elements ADD COLUMN prosody_system TEXT NOT NULL DEFAULT '${Poem.prosodySystemUnknown}'",
    );
    await db.execute(
      "ALTER TABLE poem_elements ADD COLUMN prosody_form TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE poem_elements ADD COLUMN prosody_rhyme_book TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE poem_elements ADD COLUMN prosody_note TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _addProsodyFoundationColumns(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE poem_elements ADD COLUMN prosody_supported INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      "ALTER TABLE poem_elements ADD COLUMN prosody_overrides_json TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      'ALTER TABLE poem_elements ADD COLUMN prosody_verified_at INTEGER',
    );
    await db.execute(
      "ALTER TABLE poem_elements ADD COLUMN prosody_verified_by TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _backfillProsodyMetadata(Database db) async {
    final rows = await db.query(
      'poem_elements',
      columns: ['id', 'title', 'dynasty', 'content', 'remark'],
    );
    for (final row in rows) {
      final id = row['id'];
      if (id is! int) {
        continue;
      }
      final metadata = inferProsodyMetadata(
        title: (row['title'] as String?) ?? '',
        dynasty: (row['dynasty'] as String?) ?? '',
        content: (row['content'] as String?) ?? '',
        remark: (row['remark'] as String?) ?? '',
      );
      await db.update(
        'poem_elements',
        {
          'prosody_enabled': metadata.enabled ? 1 : 0,
          'prosody_supported': metadata.supported ? 1 : 0,
          'prosody_system': metadata.system,
          'prosody_form': metadata.form,
          'prosody_rhyme_book': metadata.rhymeBook,
          'prosody_note': metadata.note,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _normalizeProsodyMetadata(Database db) async {
    await db.rawUpdate(
      "UPDATE poem_elements SET prosody_form = REPLACE(prosody_form, '候选', '') "
      "WHERE prosody_form LIKE '%候选%'",
    );
    await db.rawUpdate(
      "UPDATE poem_elements SET prosody_note = REPLACE(prosody_note, '候选', '') "
      "WHERE prosody_note LIKE '%候选%'",
    );
    await _refreshStaleCiProsodyNotes(db);
    final rows = await db.query(
      'poem_elements',
      columns: ['id', 'dynasty', 'prosody_system', 'prosody_rhyme_book'],
      where: 'prosody_system = ?',
      whereArgs: [Poem.prosodySystemRegulatedVerse],
    );
    for (final row in rows) {
      final id = row['id'];
      if (id is! int) {
        continue;
      }
      final dynasty = ((row['dynasty'] as String?) ?? '').trim();
      final rhymeBook = ((row['prosody_rhyme_book'] as String?) ?? '').trim();
      final isModern = dynasty.contains('当代') ||
          dynasty.contains('现代') ||
          dynasty.contains('近现代') ||
          dynasty.contains('现当代');
      if (isModern && rhymeBook != Poem.rhymeBookXinYun) {
        await db.update(
          'poem_elements',
          {'prosody_rhyme_book': Poem.rhymeBookXinYun},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  Future<void> _refreshStaleCiProsodyNotes(Database db) async {
    final rows = await db.query(
      'poem_elements',
      columns: [
        'id',
        'title',
        'dynasty',
        'content',
        'remark',
        'prosody_note',
      ],
      where: 'prosody_system = ?',
      whereArgs: [Poem.prosodySystemCi],
    );
    for (final row in rows) {
      final id = row['id'];
      if (id is! int) {
        continue;
      }
      final note = (row['prosody_note'] as String?) ?? '';
      if (!isStaleUnsupportedCiProsodyNote(note)) {
        continue;
      }
      final metadata = inferProsodyMetadata(
        title: (row['title'] as String?) ?? '',
        dynasty: (row['dynasty'] as String?) ?? '',
        content: (row['content'] as String?) ?? '',
        remark: (row['remark'] as String?) ?? '',
      );
      if (metadata.system != Poem.prosodySystemCi ||
          isStaleUnsupportedCiProsodyNote(metadata.note)) {
        continue;
      }
      await db.update(
        'poem_elements',
        {
          'prosody_supported': metadata.supported ? 1 : 0,
          'prosody_enabled': metadata.enabled ? 1 : 0,
          'prosody_form': metadata.form,
          'prosody_rhyme_book': metadata.rhymeBook,
          'prosody_note': metadata.note,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _backfillPoemFingerprints(DatabaseExecutor db) async {
    final rows = await db.query(
      'poem_elements',
      columns: ['id', 'author', 'content'],
    );
    for (final row in rows) {
      final id = row['id'];
      if (id is! int) {
        continue;
      }
      final fingerprint = buildPoemFingerprint(
        author: (row['author'] as String?) ?? '',
        content: (row['content'] as String?) ?? '',
      );
      await db.update(
        'poem_elements',
        fingerprint.toMap(),
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _createTrainingTables(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS training_progress (
  collection_id INTEGER PRIMARY KEY,
  poem_id INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (collection_id)
    REFERENCES poem_collections (id)
    ON DELETE CASCADE,
  FOREIGN KEY (poem_id)
    REFERENCES poem_elements (id)
    ON DELETE CASCADE
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_training_progress_updated_at '
      'ON training_progress(updated_at)',
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS training_achievements (
  poem_id INTEGER PRIMARY KEY,
  highest_level INTEGER NOT NULL DEFAULT 0,
  first_jinshi_at INTEGER,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (poem_id)
    REFERENCES poem_elements (id)
    ON DELETE CASCADE
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_training_achievements_level '
      'ON training_achievements(highest_level)',
    );
  }

  Future<void> _migratePoemsToElements(Database db) async {
    await _createPoemElementTables(db);

    final oldPoems = await db.query('poems', orderBy: 'id ASC');
    for (final oldPoem in oldPoems) {
      final oldId = oldPoem['id'] as int;
      final collectionId = oldPoem['collection_id'] as int;
      final createdAt = _intFromMap(oldPoem['created_at']);

      final poemId = await db.insert('poem_elements', {
        'identity': _legacyPoemIdentity(oldId, createdAt),
        'title': oldPoem['title'],
        'author': oldPoem['author'],
        'dynasty': oldPoem['dynasty'] ?? '',
        'preface': '',
        'content': oldPoem['content'],
        'remark': oldPoem['remark'] ?? '',
        'translation': '',
        'annotation': oldPoem['annotation'] ?? '',
        'learning_note': '',
        'appreciation': oldPoem['appreciation'] ?? '',
        'created_at': createdAt,
        'updated_at': _intFromMap(oldPoem['updated_at']),
      });

      await db.insert('collection_poems', {
        'collection_id': collectionId,
        'poem_id': poemId,
        'created_at': createdAt,
        'sort_order': createdAt,
      });
    }

    await db.execute('DROP TABLE poems');
  }

  Future<void> _ensureCollectionPoemSortOrderColumn(
    DatabaseExecutor db,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info(collection_poems)');
    final hasSortOrder = columns.any((column) => column['name'] == 'sort_order');
    if (!hasSortOrder) {
      await db.execute(
        'ALTER TABLE collection_poems '
        'ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
      );
    }
    await _backfillCollectionPoemSortOrder(db);
  }

  Future<void> _backfillCollectionPoemSortOrder(DatabaseExecutor db) async {
    final collectionRows = await db.rawQuery(
      'SELECT DISTINCT collection_id FROM collection_poems '
      'ORDER BY collection_id ASC',
    );

    for (final collectionRow in collectionRows) {
      final collectionId = collectionRow['collection_id'];
      if (collectionId is! int) {
        continue;
      }

      final rows = await db.query(
        'collection_poems',
        columns: ['poem_id'],
        where: 'collection_id = ?',
        whereArgs: [collectionId],
        orderBy: 'sort_order ASC, created_at ASC, poem_id ASC',
      );

      for (var index = 0; index < rows.length; index += 1) {
        final poemId = rows[index]['poem_id'];
        if (poemId is! int) {
          continue;
        }
        await db.update(
          'collection_poems',
          {'sort_order': index},
          where: 'collection_id = ? AND poem_id = ?',
          whereArgs: [collectionId, poemId],
        );
      }
    }
  }

  Future<List<PoemCollection>> getCollections() async {
    final db = await database;
    final rows = await db.query(
      'poem_collections',
      orderBy: 'updated_at DESC, name ASC',
    );
    return rows.map(PoemCollection.fromMap).toList();
  }

  Future<List<ApiConfig>> getApiConfigs({String query = ''}) async {
    final db = await database;
    final keyword = query.trim();

    if (keyword.isEmpty) {
      final rows = await db.query(
        'api_configs',
        orderBy: 'is_active DESC, updated_at DESC, name ASC',
      );
      return rows.map(ApiConfig.fromMap).toList();
    }

    final like = '%$keyword%';
    final rows = await db.query(
      'api_configs',
      where: '''
name LIKE ?
OR base_url LIKE ?
OR chat_model LIKE ?
OR embedding_model LIKE ?
OR search_provider LIKE ?
''',
      whereArgs: [like, like, like, like, like],
      orderBy: 'is_active DESC, updated_at DESC, name ASC',
    );
    return rows.map(ApiConfig.fromMap).toList();
  }

  Future<ApiConfig?> getActiveApiConfig() async {
    final db = await database;
    final activeRows = await db.query(
      'api_configs',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'updated_at DESC, name ASC',
      limit: 1,
    );
    if (activeRows.isNotEmpty) {
      return ApiConfig.fromMap(activeRows.first);
    }

    final rows = await db.query(
      'api_configs',
      orderBy: 'updated_at DESC, name ASC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ApiConfig.fromMap(rows.first);
  }

  Future<List<Map<String, Object?>>> getPoemAgentMessages(
    String scopeKey,
  ) async {
    final db = await database;
    return db.query(
      'poem_agent_messages',
      columns: ['role', 'content'],
      where: 'scope_key = ?',
      whereArgs: [scopeKey],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<void> addPoemAgentMessage({
    required String scopeKey,
    required String role,
    required String content,
  }) async {
    if (content.trim().isEmpty) {
      return;
    }

    final db = await database;
    await db.insert('poem_agent_messages', {
      'scope_key': scopeKey,
      'role': role,
      'content': content,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> clearPoemAgentMessages(String scopeKey) async {
    final db = await database;
    await db.delete(
      'poem_agent_messages',
      where: 'scope_key = ?',
      whereArgs: [scopeKey],
    );
  }

  Future<void> clearAllPoemAgentMessages() async {
    final db = await database;
    await db.delete('poem_agent_messages');
  }

  Future<int?> getLastLearningCollectionId() async {
    final db = await database;
    final rows = await db.rawQuery('''
SELECT lp.collection_id
FROM learning_progress lp
INNER JOIN poem_collections pc ON pc.id = lp.collection_id
ORDER BY lp.updated_at DESC
LIMIT 1
''');
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['collection_id'] as int?;
  }

  Future<int?> getLearningProgressPoemId(int collectionId) async {
    final db = await database;
    final rows = await db.query(
      'learning_progress',
      columns: ['poem_id'],
      where: 'collection_id = ?',
      whereArgs: [collectionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['poem_id'] as int?;
  }

  Future<void> saveLearningProgress({
    required int collectionId,
    required int poemId,
  }) async {
    final db = await database;
    await db.insert(
      'learning_progress',
      {
        'collection_id': collectionId,
        'poem_id': poemId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int?> getLastTrainingCollectionId() async {
    final db = await database;
    final rows = await db.rawQuery('''
SELECT tp.collection_id
FROM training_progress tp
INNER JOIN poem_collections pc ON pc.id = tp.collection_id
ORDER BY tp.updated_at DESC
LIMIT 1
''');
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['collection_id'] as int?;
  }

  Future<int?> getTrainingProgressPoemId(int collectionId) async {
    final db = await database;
    final rows = await db.query(
      'training_progress',
      columns: ['poem_id'],
      where: 'collection_id = ?',
      whereArgs: [collectionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['poem_id'] as int?;
  }

  Future<void> saveTrainingProgress({
    required int collectionId,
    required int poemId,
  }) async {
    final db = await database;
    await db.insert(
      'training_progress',
      {
        'collection_id': collectionId,
        'poem_id': poemId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<int, int>> getTrainingAchievements(
    Iterable<int> poemIds,
  ) async {
    final ids = poemIds.toSet();
    if (ids.isEmpty) {
      return const <int, int>{};
    }

    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await db.rawQuery(
      '''
SELECT poem_id, highest_level
FROM training_achievements
WHERE poem_id IN ($placeholders)
''',
      ids.toList(),
    );

    return {
      for (final row in rows)
        if (row['poem_id'] is int && row['highest_level'] is int)
          row['poem_id'] as int: row['highest_level'] as int,
    };
  }

  Future<int> saveTrainingAchievement({
    required int poemId,
    required int level,
  }) async {
    final normalizedLevel = level.clamp(0, 4).toInt();
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    var finalLevel = normalizedLevel;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'training_achievements',
        where: 'poem_id = ?',
        whereArgs: [poemId],
        limit: 1,
      );

      if (rows.isEmpty) {
        await txn.insert('training_achievements', {
          'poem_id': poemId,
          'highest_level': normalizedLevel,
          'first_jinshi_at': normalizedLevel >= 4 ? now : null,
          'updated_at': now,
        });
        return;
      }

      final currentLevel = (rows.first['highest_level'] as int?) ?? 0;
      finalLevel = currentLevel > normalizedLevel
          ? currentLevel
          : normalizedLevel;
      if (finalLevel == currentLevel) {
        await txn.update(
          'training_achievements',
          {'updated_at': now},
          where: 'poem_id = ?',
          whereArgs: [poemId],
        );
        return;
      }

      await txn.update(
        'training_achievements',
        {
          'highest_level': finalLevel,
          if (finalLevel >= 4 && currentLevel < 4) 'first_jinshi_at': now,
          'updated_at': now,
        },
        where: 'poem_id = ?',
        whereArgs: [poemId],
      );
    });

    return finalLevel;
  }

  Future<int> getJinshiPointCount() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) FROM training_achievements WHERE first_jinshi_at IS NOT NULL',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<List<JinshiAchievementEntry>> getJinshiAchievementHistory() async {
    final db = await database;
    final rows = await db.rawQuery('''
SELECT pe.*, COALESCE(MIN(cp.collection_id), 0) AS collection_id,
  ta.first_jinshi_at AS first_jinshi_at
FROM training_achievements ta
INNER JOIN poem_elements pe ON pe.id = ta.poem_id
LEFT JOIN collection_poems cp ON cp.poem_id = pe.id
WHERE ta.first_jinshi_at IS NOT NULL
GROUP BY pe.id
ORDER BY ta.first_jinshi_at DESC, pe.title ASC
''');

    return rows.map((row) {
      final firstJinshiAt = DateTime.fromMillisecondsSinceEpoch(
        _intFromMap(row['first_jinshi_at']),
      );
      return JinshiAchievementEntry(
        poem: Poem.fromMap(row),
        firstJinshiAt: firstJinshiAt,
      );
    }).toList();
  }

  Future<int> currentDatabaseVersion() async {
    final db = await database;
    return db.getVersion();
  }

  Future<Map<String, List<Map<String, Object?>>>> exportBackupTables() async {
    final db = await database;
    final data = <String, List<Map<String, Object?>>>{};
    for (final tableName in backupTableNames) {
      data[tableName] = await db.query(
        tableName,
        orderBy: _backupTableOrderBy[tableName],
      );
    }
    return data;
  }

  Future<void> importBackupTables(
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    final db = await database;
    final tableColumns = <String, Set<String>>{};
    for (final tableName in backupTableNames) {
      final columns = await db.rawQuery('PRAGMA table_info($tableName)');
      tableColumns[tableName] = {
        for (final column in columns) column['name'] as String,
      };
    }

    await db.transaction((txn) async {
      for (final tableName in _backupDeleteOrder) {
        await txn.delete(tableName);
      }

      for (final tableName in _backupInsertOrder) {
        final allowedColumns = tableColumns[tableName] ?? const <String>{};
        final rows = tables[tableName] ?? const <Map<String, Object?>>[];
        for (final row in rows) {
          final filteredRow = <String, Object?>{
            for (final entry in row.entries)
              if (allowedColumns.contains(entry.key)) entry.key: entry.value,
          };
          if (filteredRow.isEmpty) {
            continue;
          }
          await txn.insert(
            tableName,
            filteredRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await _backfillCollectionPoemSortOrder(txn);
      await _backfillPoemFingerprints(txn);
    });
  }

  Future<int> createApiConfig({
    required String name,
    required String apiKey,
    required String baseUrl,
    required String chatModel,
    String embeddingModel = '',
    String searchProvider = ApiConfig.searchProviderNone,
    String tavilySearchApiKey = '',
    String bochaSearchApiKey = '',
    int searchMaxResults = 5,
    bool searchIncludeRawContent = false,
    bool isActive = false,
  }) async {
    final now = DateTime.now();
    final db = await database;
    final existingCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM api_configs'),
        ) ??
        0;

    final config = ApiConfig(
      name: name.trim(),
      apiKey: apiKey.trim(),
      baseUrl: _normalizeBaseUrl(baseUrl),
      chatModel: chatModel.trim(),
      embeddingModel: embeddingModel.trim(),
      searchProvider: searchProvider,
      tavilySearchApiKey: tavilySearchApiKey.trim(),
      bochaSearchApiKey: bochaSearchApiKey.trim(),
      searchMaxResults: _normalizeSearchMaxResults(searchMaxResults),
      searchIncludeRawContent: searchIncludeRawContent,
      isActive: isActive || existingCount == 0,
      createdAt: now,
      updatedAt: now,
    );

    return db.transaction<int>((txn) async {
      if (config.isActive) {
        await txn.update('api_configs', {'is_active': 0});
      }
      return txn.insert('api_configs', config.toMap());
    });
  }

  Future<void> updateApiConfig(ApiConfig config) async {
    final id = config.id;
    if (id == null) {
      throw ArgumentError('Cannot update an API config without an id.');
    }

    final updatedConfig = config.copyWith(
      name: config.name.trim(),
      apiKey: config.apiKey.trim(),
      baseUrl: _normalizeBaseUrl(config.baseUrl),
      chatModel: config.chatModel.trim(),
      embeddingModel: config.embeddingModel.trim(),
      searchProvider: config.searchProvider,
      tavilySearchApiKey: config.tavilySearchApiKey.trim(),
      bochaSearchApiKey: config.bochaSearchApiKey.trim(),
      searchMaxResults: _normalizeSearchMaxResults(config.searchMaxResults),
      searchIncludeRawContent: config.searchIncludeRawContent,
      updatedAt: DateTime.now(),
    );
    final db = await database;
    await db.transaction((txn) async {
      if (updatedConfig.isActive) {
        await txn.update('api_configs', {'is_active': 0});
      }
      await txn.update(
        'api_configs',
        updatedConfig.toMap(),
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> deleteApiConfig(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'api_configs',
        columns: ['is_active'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.delete('api_configs', where: 'id = ?', whereArgs: [id]);

      final wasActive = rows.isNotEmpty && rows.first['is_active'] == 1;
      if (wasActive) {
        final replacementRows = await txn.query(
          'api_configs',
          columns: ['id'],
          orderBy: 'updated_at DESC, name ASC',
          limit: 1,
        );
        if (replacementRows.isNotEmpty) {
          await txn.update(
            'api_configs',
            {'is_active': 1},
            where: 'id = ?',
            whereArgs: [replacementRows.first['id']],
          );
        }
      }
    });
  }

  Future<void> setActiveApiConfig(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('api_configs', {'is_active': 0});
      await txn.update(
        'api_configs',
        {
          'is_active': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<int> createCollection({
    required String name,
    String description = '',
    bool isFavorites = false,
  }) async {
    final now = DateTime.now();
    final collection = PoemCollection(
      name: name.trim(),
      description: description.trim(),
      isFavorites: isFavorites,
      createdAt: now,
      updatedAt: now,
    );
    final db = await database;
    return db.insert('poem_collections', collection.toMap());
  }

  Future<PoemCollection> getOrCreateFavoritesCollection() async {
    final db = await database;
    final favoriteRows = await db.query(
      'poem_collections',
      where: 'is_favorites = ?',
      whereArgs: [1],
      orderBy: 'updated_at DESC, id ASC',
      limit: 1,
    );
    if (favoriteRows.isNotEmpty) {
      return PoemCollection.fromMap(favoriteRows.first);
    }

    final namedRows = await db.query(
      'poem_collections',
      where: 'name = ?',
      whereArgs: ['收藏夹'],
      orderBy: 'updated_at DESC, id ASC',
      limit: 1,
    );
    if (namedRows.isNotEmpty) {
      final row = namedRows.first;
      final id = row['id'] as int;
      await db.update(
        'poem_collections',
        {
          'is_favorites': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      final updatedRows = await db.query(
        'poem_collections',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return PoemCollection.fromMap(updatedRows.first);
    }

    final now = DateTime.now();
    final collection = PoemCollection(
      name: '收藏夹',
      description: '收藏的诗词',
      isFavorites: true,
      createdAt: now,
      updatedAt: now,
    );
    final id = await db.insert('poem_collections', collection.toMap());
    return collection.copyWith(id: id);
  }

  Future<void> updateCollection(PoemCollection collection) async {
    final id = collection.id;
    if (id == null) {
      throw ArgumentError('Cannot update a collection without an id.');
    }

    final db = await database;
    await db.update(
      'poem_collections',
      collection.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCollection(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('poem_collections', where: 'id = ?', whereArgs: [id]);
      await _deleteOrphanedPoems(txn);
    });
  }

  Future<List<Poem>> getPoems(int collectionId, {String query = ''}) async {
    final db = await database;
    final keyword = query.trim();

    if (keyword.isEmpty) {
      final rows = await db.rawQuery(
        '''
SELECT pe.*, cp.collection_id
FROM poem_elements pe
INNER JOIN collection_poems cp ON cp.poem_id = pe.id
WHERE cp.collection_id = ?
ORDER BY cp.sort_order ASC, cp.created_at ASC, pe.title ASC
''',
        [collectionId],
      );
      return rows.map(Poem.fromMap).toList();
    }

    final like = '%$keyword%';
    final rows = await db.rawQuery(
      '''
SELECT pe.*, cp.collection_id
FROM poem_elements pe
INNER JOIN collection_poems cp ON cp.poem_id = pe.id
WHERE cp.collection_id = ?
AND (
  pe.title LIKE ?
  OR pe.author LIKE ?
  OR pe.preface LIKE ?
  OR pe.content LIKE ?
  OR pe.remark LIKE ?
  OR pe.translation LIKE ?
  OR pe.annotation LIKE ?
  OR pe.learning_note LIKE ?
  OR pe.appreciation LIKE ?
)
ORDER BY cp.sort_order ASC, cp.created_at ASC, pe.title ASC
''',
      [collectionId, like, like, like, like, like, like, like, like, like],
    );
    return rows.map(Poem.fromMap).toList();
  }

  Future<List<DuplicatePoemCandidate>> findPotentialDuplicatePoems({
    required String author,
    required String content,
    int? excludePoemId,
    int limit = 8,
  }) async {
    final fingerprint = buildPoemFingerprint(author: author, content: content);
    final conditions = <String>[];
    final args = <Object?>[];
    if (excludePoemId != null) {
      conditions.add('pe.id != ?');
      args.add(excludePoemId);
    }
    final duplicateConditions = <String>[];
    if (fingerprint.exactContentHash.isNotEmpty) {
      duplicateConditions.add('pe.exact_content_hash = ?');
      args.add(fingerprint.exactContentHash);
    }
    if (fingerprint.workFingerprint.isNotEmpty) {
      duplicateConditions.add('pe.work_fingerprint = ?');
      args.add(fingerprint.workFingerprint);
    }
    if (fingerprint.contentShapeHash.isNotEmpty) {
      duplicateConditions.add('pe.content_shape_hash = ?');
      args.add(fingerprint.contentShapeHash);
    }
    if (duplicateConditions.isEmpty) {
      return const <DuplicatePoemCandidate>[];
    }
    conditions.add('(${duplicateConditions.join(' OR ')})');

    final db = await database;
    final rows = await db.rawQuery(
      '''
SELECT pe.*,
  COALESCE(MIN(cp.collection_id), 0) AS collection_id,
  GROUP_CONCAT(DISTINCT pc.name) AS collection_names
FROM poem_elements pe
LEFT JOIN collection_poems cp ON cp.poem_id = pe.id
LEFT JOIN poem_collections pc ON pc.id = cp.collection_id
WHERE ${conditions.join(' AND ')}
GROUP BY pe.id
LIMIT ?
''',
      [...args, limit],
    );

    final candidates = <DuplicatePoemCandidate>[];
    for (final row in rows) {
      final exactHash = (row['exact_content_hash'] as String?) ?? '';
      final workHash = (row['work_fingerprint'] as String?) ?? '';
      final shapeHash = (row['content_shape_hash'] as String?) ?? '';
      late final DuplicatePoemMatchLevel level;
      late final String reason;
      if (fingerprint.exactContentHash.isNotEmpty &&
          exactHash == fingerprint.exactContentHash) {
        level = DuplicatePoemMatchLevel.exact;
        reason = '正文几乎一致';
      } else if (fingerprint.workFingerprint.isNotEmpty &&
          workHash == fingerprint.workFingerprint) {
        level = DuplicatePoemMatchLevel.work;
        reason = '作者与首末句一致';
      } else if (fingerprint.contentShapeHash.isNotEmpty &&
          shapeHash == fingerprint.contentShapeHash) {
        level = DuplicatePoemMatchLevel.shape;
        reason = '首末句与结构相近';
      } else {
        continue;
      }
      final collectionNames = ((row['collection_names'] as String?) ?? '')
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      candidates.add(
        DuplicatePoemCandidate(
          poem: Poem.fromMap(row),
          collectionNames: collectionNames,
          reason: reason,
          level: level,
        ),
      );
    }
    candidates.sort((a, b) {
      final levelCompare = a.level.index.compareTo(b.level.index);
      if (levelCompare != 0) {
        return levelCompare;
      }
      return b.poem.updatedAt.compareTo(a.poem.updatedAt);
    });
    return candidates.take(limit).toList(growable: false);
  }

  Future<int> getCollectionPoemCount(int collectionId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM collection_poems WHERE collection_id = ?',
      [collectionId],
    );
    final value = rows.isEmpty ? null : rows.first['count'];
    if (value is int) {
      return value;
    }
    return 0;
  }

  Future<Poem?> getPoemById(int poemId, {int? collectionId}) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
SELECT pe.*, cp.collection_id
FROM poem_elements pe
INNER JOIN collection_poems cp ON cp.poem_id = pe.id
WHERE pe.id = ?
${collectionId == null ? '' : 'AND cp.collection_id = ?'}
ORDER BY cp.sort_order ASC, cp.created_at ASC
LIMIT 1
''',
      collectionId == null ? [poemId] : [poemId, collectionId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return Poem.fromMap(rows.first);
  }

  Future<Set<int>> getPoemCollectionIds(int poemId) async {
    final db = await database;
    final rows = await db.query(
      'collection_poems',
      columns: ['collection_id'],
      where: 'poem_id = ?',
      whereArgs: [poemId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => row['collection_id'])
        .whereType<int>()
        .toSet();
  }

  Future<int> createPoem({
    required int collectionId,
    required String title,
    required String author,
    required String dynasty,
    String preface = '',
    required String content,
    String remark = '',
    String translation = '',
    String annotation = '',
    String learningNote = '',
    String appreciation = '',
    bool? prosodySupported,
    bool? prosodyEnabled,
    String? prosodySystem,
    String? prosodyForm,
    String? prosodyRhymeBook,
    String? prosodyNote,
    String prosodyOverridesJson = '',
    DateTime? prosodyVerifiedAt,
    String prosodyVerifiedBy = '',
  }) async {
    final now = DateTime.now();
    final createdAt = now.millisecondsSinceEpoch;
    final inferredProsody = inferProsodyMetadata(
      title: title,
      dynasty: dynasty,
      content: content,
      remark: remark,
    );
    final resolvedSystem =
        (prosodySystem == null || prosodySystem.trim().isEmpty)
            ? inferredProsody.system
            : prosodySystem.trim();
    final hasExplicitProsodyMetadata =
        (prosodySystem?.trim().isNotEmpty ?? false) ||
            (prosodyForm?.trim().isNotEmpty ?? false) ||
            (prosodyRhymeBook?.trim().isNotEmpty ?? false) ||
            prosodyOverridesJson.trim().isNotEmpty ||
            prosodyVerifiedAt != null ||
            prosodyVerifiedBy.trim().isNotEmpty;
    final resolvedSupported = prosodySupported ??
        (hasExplicitProsodyMetadata &&
                resolvedSystem != Poem.prosodySystemUnknown &&
                resolvedSystem != Poem.prosodySystemUnsupported
            ? true
            : inferredProsody.supported);
    final fingerprint = buildPoemFingerprint(
      author: author,
      content: content,
    );
    final poem = Poem(
      collectionId: collectionId,
      identity: _generatePoemIdentity(),
      title: title.trim(),
      author: author.trim(),
      dynasty: dynasty.trim(),
      preface: preface.trim(),
      content: content.trim(),
      remark: remark.trim(),
      translation: translation.trim(),
      annotation: annotation.trim(),
      learningNote: learningNote.trim(),
      appreciation: appreciation.trim(),
      prosodySupported: resolvedSupported,
      prosodyEnabled: resolvedSupported &&
          (prosodyEnabled ??
              (hasExplicitProsodyMetadata ? true : inferredProsody.enabled)),
      prosodySystem: resolvedSystem,
      prosodyForm: (prosodyForm == null || prosodyForm.trim().isEmpty)
          ? inferredProsody.form
          : prosodyForm.trim(),
      prosodyRhymeBook:
          (prosodyRhymeBook == null || prosodyRhymeBook.trim().isEmpty)
              ? inferredProsody.rhymeBook
              : prosodyRhymeBook.trim(),
      prosodyNote: (prosodyNote == null || prosodyNote.trim().isEmpty)
          ? inferredProsody.note
          : prosodyNote.trim(),
      prosodyOverridesJson: prosodyOverridesJson.trim(),
      prosodyVerifiedAt: prosodyVerifiedAt,
      prosodyVerifiedBy: prosodyVerifiedBy.trim(),
      exactContentHash: fingerprint.exactContentHash,
      workFingerprint: fingerprint.workFingerprint,
      contentShapeHash: fingerprint.contentShapeHash,
      createdAt: now,
      updatedAt: now,
    );

    final db = await database;
    final id = await db.transaction<int>((txn) async {
      final poemId = await txn.insert('poem_elements', poem.toElementMap());
      final sortOrder = await _nextCollectionPoemSortOrder(txn, collectionId);
      await txn.insert('collection_poems', {
        'collection_id': collectionId,
        'poem_id': poemId,
        'created_at': createdAt,
        'sort_order': sortOrder,
      });
      return poemId;
    });
    await _touchCollection(collectionId);
    return id;
  }

  Future<void> updatePoem(Poem poem) async {
    final id = poem.id;
    if (id == null) {
      throw ArgumentError('Cannot update a poem without an id.');
    }

    final fingerprint = buildPoemFingerprintFromPoem(poem);
    final updatedPoem = poem.copyWith(
      exactContentHash: fingerprint.exactContentHash,
      workFingerprint: fingerprint.workFingerprint,
      contentShapeHash: fingerprint.contentShapeHash,
      updatedAt: DateTime.now(),
    );
    final db = await database;
    await db.update(
      'poem_elements',
      updatedPoem.toElementMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    await _touchCollection(updatedPoem.collectionId);
  }

  Future<void> deletePoem(Poem poem) async {
    final id = poem.id;
    if (id == null) {
      return;
    }

    await removePoemsFromCollection(
      collectionId: poem.collectionId,
      poemIds: [id],
    );
  }

  Future<List<int>> addPoemsToCollection({
    required int collectionId,
    required Iterable<int> poemIds,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final uniquePoemIds = _uniqueIntsInOrder(poemIds);
    final addedPoemIds = <int>[];

    await db.transaction((txn) async {
      var sortOrder = await _nextCollectionPoemSortOrder(txn, collectionId);
      for (final poemId in uniquePoemIds) {
        final poemRows = await txn.query(
          'poem_elements',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [poemId],
          limit: 1,
        );
        if (poemRows.isEmpty) {
          continue;
        }

        final relationRows = await txn.query(
          'collection_poems',
          columns: ['poem_id'],
          where: 'collection_id = ? AND poem_id = ?',
          whereArgs: [collectionId, poemId],
          limit: 1,
        );
        if (relationRows.isNotEmpty) {
          continue;
        }

        await txn.insert(
          'collection_poems',
          {
            'collection_id': collectionId,
            'poem_id': poemId,
            'created_at': now,
            'sort_order': sortOrder,
          },
        );
        addedPoemIds.add(poemId);
        sortOrder += 1;
      }
    });

    if (addedPoemIds.isNotEmpty) {
      await _touchCollection(collectionId);
    }
    return addedPoemIds;
  }

  Future<void> movePoemInCollection({
    required int collectionId,
    required int poemId,
    required int targetIndex,
  }) async {
    final db = await database;
    var moved = false;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'collection_poems',
        columns: ['poem_id'],
        where: 'collection_id = ?',
        whereArgs: [collectionId],
        orderBy: 'sort_order ASC, created_at ASC, poem_id ASC',
      );
      final poemIds = rows
          .map((row) => row['poem_id'])
          .whereType<int>()
          .toList(growable: true);
      final oldIndex = poemIds.indexOf(poemId);
      if (oldIndex < 0) {
        return;
      }

      poemIds.removeAt(oldIndex);
      final clampedIndex = targetIndex.clamp(0, poemIds.length).toInt();
      poemIds.insert(clampedIndex, poemId);
      moved = oldIndex != clampedIndex;

      for (var index = 0; index < poemIds.length; index += 1) {
        await txn.update(
          'collection_poems',
          {'sort_order': index},
          where: 'collection_id = ? AND poem_id = ?',
          whereArgs: [collectionId, poemIds[index]],
        );
      }
    });

    if (moved) {
      await _touchCollection(collectionId);
    }
  }

  Future<int> removePoemsFromCollection({
    required int collectionId,
    required Iterable<int> poemIds,
  }) async {
    final db = await database;
    final uniquePoemIds = poemIds.toSet();
    var removedCount = 0;

    await db.transaction((txn) async {
      for (final poemId in uniquePoemIds) {
        removedCount += await txn.delete(
          'collection_poems',
          where: 'collection_id = ? AND poem_id = ?',
          whereArgs: [collectionId, poemId],
        );
        await _deletePoemIfOrphaned(txn, poemId);
      }
    });

    if (removedCount > 0) {
      await _touchCollection(collectionId);
    }
    return removedCount;
  }

  Future<void> _touchCollection(int collectionId) async {
    final db = await database;
    await db.update(
      'poem_collections',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [collectionId],
    );
  }

  Future<int> _nextCollectionPoemSortOrder(
    DatabaseExecutor db,
    int collectionId,
  ) async {
    final rows = await db.rawQuery(
      'SELECT MAX(sort_order) FROM collection_poems WHERE collection_id = ?',
      [collectionId],
    );
    return (Sqflite.firstIntValue(rows) ?? -1) + 1;
  }

  Future<void> _deletePoemIfOrphaned(DatabaseExecutor db, int poemId) async {
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) FROM collection_poems WHERE poem_id = ?',
      [poemId],
    );
    final remainingReferences = Sqflite.firstIntValue(countRows) ?? 0;
    if (remainingReferences == 0) {
      await db.delete('poem_elements', where: 'id = ?', whereArgs: [poemId]);
    }
  }

  Future<void> _deleteOrphanedPoems(DatabaseExecutor db) async {
    await db.execute('''
DELETE FROM poem_elements
WHERE id NOT IN (
  SELECT poem_id FROM collection_poems
)
''');
  }
}

final _poemIdentityRandom = Random.secure();

String _generatePoemIdentity() {
  final bytes = List<int>.generate(
    16,
    (_) => _poemIdentityRandom.nextInt(256),
  );
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  return [
    hex.substring(0, 8),
    hex.substring(8, 12),
    hex.substring(12, 16),
    hex.substring(16, 20),
    hex.substring(20),
  ].join('-');
}

String _legacyPoemIdentity(int oldId, int createdAt) {
  return 'legacy-$createdAt-$oldId';
}

List<int> _uniqueIntsInOrder(Iterable<int> values) {
  final seen = <int>{};
  final result = <int>[];
  for (final value in values) {
    if (seen.add(value)) {
      result.add(value);
    }
  }
  return result;
}

int _intFromMap(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value) ?? DateTime.now().millisecondsSinceEpoch;
  }
  return DateTime.now().millisecondsSinceEpoch;
}

String _normalizeBaseUrl(String value) {
  var normalized = value.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

int _normalizeSearchMaxResults(int value) {
  if (value < 1) {
    return 1;
  }
  if (value > 10) {
    return 10;
  }
  return value;
}

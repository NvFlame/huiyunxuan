import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/api_config.dart';
import '../models/poem.dart';
import '../models/poem_collection.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

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
      version: 8,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE poem_collections (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

        await _createPoemElementTables(db);
        await _createApiConfigTable(db);
        await _createPoemAgentMessageTable(db);
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
  content TEXT NOT NULL,
  remark TEXT NOT NULL DEFAULT '',
  translation TEXT NOT NULL DEFAULT '',
  annotation TEXT NOT NULL DEFAULT '',
  appreciation TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await db.execute('''
CREATE TABLE collection_poems (
  collection_id INTEGER NOT NULL,
  poem_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
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
        'content': oldPoem['content'],
        'remark': oldPoem['remark'] ?? '',
        'translation': '',
        'annotation': oldPoem['annotation'] ?? '',
        'appreciation': oldPoem['appreciation'] ?? '',
        'created_at': createdAt,
        'updated_at': _intFromMap(oldPoem['updated_at']),
      });

      await db.insert('collection_poems', {
        'collection_id': collectionId,
        'poem_id': poemId,
        'created_at': createdAt,
      });
    }

    await db.execute('DROP TABLE poems');
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
  }) async {
    final now = DateTime.now();
    final collection = PoemCollection(
      name: name.trim(),
      description: description.trim(),
      createdAt: now,
      updatedAt: now,
    );
    final db = await database;
    return db.insert('poem_collections', collection.toMap());
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
ORDER BY pe.updated_at DESC, pe.title ASC
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
  OR pe.content LIKE ?
  OR pe.remark LIKE ?
  OR pe.translation LIKE ?
  OR pe.annotation LIKE ?
  OR pe.appreciation LIKE ?
)
ORDER BY pe.updated_at DESC, pe.title ASC
''',
      [collectionId, like, like, like, like, like, like, like],
    );
    return rows.map(Poem.fromMap).toList();
  }

  Future<int> createPoem({
    required int collectionId,
    required String title,
    required String author,
    required String dynasty,
    required String content,
    String remark = '',
    String translation = '',
    String annotation = '',
    String appreciation = '',
  }) async {
    final now = DateTime.now();
    final createdAt = now.millisecondsSinceEpoch;
    final poem = Poem(
      collectionId: collectionId,
      identity: _generatePoemIdentity(),
      title: title.trim(),
      author: author.trim(),
      dynasty: dynasty.trim(),
      content: content.trim(),
      remark: remark.trim(),
      translation: translation.trim(),
      annotation: annotation.trim(),
      appreciation: appreciation.trim(),
      createdAt: now,
      updatedAt: now,
    );

    final db = await database;
    final id = await db.transaction<int>((txn) async {
      final poemId = await txn.insert('poem_elements', poem.toElementMap());
      await txn.insert('collection_poems', {
        'collection_id': collectionId,
        'poem_id': poemId,
        'created_at': createdAt,
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

    final updatedPoem = poem.copyWith(updatedAt: DateTime.now());
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
    final uniquePoemIds = poemIds.toSet();
    final addedPoemIds = <int>[];

    await db.transaction((txn) async {
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
          },
        );
        addedPoemIds.add(poemId);
      }
    });

    if (addedPoemIds.isNotEmpty) {
      await _touchCollection(collectionId);
    }
    return addedPoemIds;
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

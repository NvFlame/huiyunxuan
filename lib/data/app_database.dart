import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
      version: 1,
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

        await db.execute('''
CREATE TABLE poems (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  collection_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  dynasty TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL,
  remark TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (collection_id)
    REFERENCES poem_collections (id)
    ON DELETE CASCADE
)
''');

        await db.execute(
          'CREATE INDEX idx_poems_collection_id ON poems(collection_id)',
        );
        await db.execute('CREATE INDEX idx_poems_title ON poems(title)');
        await db.execute('CREATE INDEX idx_poems_author ON poems(author)');
      },
    );
  }

  Future<List<PoemCollection>> getCollections() async {
    final db = await database;
    final rows = await db.query(
      'poem_collections',
      orderBy: 'updated_at DESC, name ASC',
    );
    return rows.map(PoemCollection.fromMap).toList();
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
    await db.delete('poem_collections', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Poem>> getPoems(int collectionId, {String query = ''}) async {
    final db = await database;
    final keyword = query.trim();

    if (keyword.isEmpty) {
      final rows = await db.query(
        'poems',
        where: 'collection_id = ?',
        whereArgs: [collectionId],
        orderBy: 'updated_at DESC, title ASC',
      );
      return rows.map(Poem.fromMap).toList();
    }

    final like = '%$keyword%';
    final rows = await db.query(
      'poems',
      where: '''
collection_id = ?
AND (
  title LIKE ?
  OR author LIKE ?
  OR content LIKE ?
  OR remark LIKE ?
)
''',
      whereArgs: [collectionId, like, like, like, like],
      orderBy: 'updated_at DESC, title ASC',
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
  }) async {
    final now = DateTime.now();
    final poem = Poem(
      collectionId: collectionId,
      title: title.trim(),
      author: author.trim(),
      dynasty: dynasty.trim(),
      content: content.trim(),
      remark: remark.trim(),
      createdAt: now,
      updatedAt: now,
    );

    final db = await database;
    final id = await db.insert('poems', poem.toMap());
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
      'poems',
      updatedPoem.toMap(),
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

    final db = await database;
    await db.delete('poems', where: 'id = ?', whereArgs: [id]);
    await _touchCollection(poem.collectionId);
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
}

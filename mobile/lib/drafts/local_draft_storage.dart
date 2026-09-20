import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// An edit that has not reached the server yet.
class PendingSave {
  const PendingSave({
    required this.kind,
    required this.key,
    required this.inspectionId,
    required this.payload,
    required this.updatedAt,
  });

  /// 'response' (key = response id) or 'comment' (key = inspection id).
  final String kind;
  final int key;
  final int inspectionId;
  final Map<String, dynamic> payload;
  final DateTime updatedAt;
}

/// Everything the app keeps on the device so unfinished work survives being
/// offline or closed: a copy of each open inspection, the edits that still
/// have to be sent, and which user they belong to.
class LocalDraftStorage {
  LocalDraftStorage({this.databasePath});

  /// Overridable for tests (for example `inMemoryDatabasePath`).
  final String? databasePath;
  Database? _database;

  static const _ownerKey = 'owner_user_id';

  Future<Database> get database async {
    _database ??= await openDatabase(
      databasePath ??
          path.join(await getDatabasesPath(), 'inspection_drafts.db'),
      version: 2,
      onCreate: (db, _) async {
        await _createDrafts(db);
        await _createPendingAndMeta(db);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await _createPendingAndMeta(db);
      },
    );
    return _database!;
  }

  static Future<void> _createDrafts(Database db) => db.execute('''
    CREATE TABLE drafts(
      inspection_id INTEGER PRIMARY KEY,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  static Future<void> _createPendingAndMeta(Database db) async {
    await db.execute('''
      CREATE TABLE pending_saves(
        kind TEXT NOT NULL,
        key INTEGER NOT NULL,
        inspection_id INTEGER NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (kind, key)
      )
    ''');
    await db.execute('''
      CREATE TABLE meta(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  // --- copies of open inspections (for resuming without a connection) ---

  Future<void> saveDraft(int inspectionId, Map<String, dynamic> payload) async {
    final db = await database;
    await db.insert(
      'drafts',
      {
        'inspection_id': inspectionId,
        'payload': jsonEncode(payload),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadDraft(int inspectionId) async {
    final db = await database;
    final rows = await db.query('drafts',
        where: 'inspection_id = ?', whereArgs: [inspectionId], limit: 1);
    return rows.isEmpty ? null : _decode(rows.first['payload']);
  }

  /// Newest first.
  Future<List<Map<String, dynamic>>> loadDrafts() async {
    final db = await database;
    final rows = await db.query('drafts', orderBy: 'updated_at DESC');
    return [
      for (final row in rows)
        if (_decode(row['payload']) case final payload?) payload,
    ];
  }

  Future<void> clearDraft(int inspectionId) async {
    final db = await database;
    await db.delete('drafts',
        where: 'inspection_id = ?', whereArgs: [inspectionId]);
  }

  // --- edits waiting to be sent ---

  Future<void> savePending(
    String kind,
    int key,
    int inspectionId,
    Map<String, dynamic> payload,
  ) async {
    final db = await database;
    await db.insert(
      'pending_saves',
      {
        'kind': kind,
        'key': key,
        'inspection_id': inspectionId,
        'payload': jsonEncode(payload),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePending(String kind, int key) async {
    final db = await database;
    await db.delete('pending_saves',
        where: 'kind = ? AND key = ?', whereArgs: [kind, key]);
  }

  /// Oldest first, so edits are replayed in the order they were made.
  Future<List<PendingSave>> loadPending() async {
    final db = await database;
    final rows = await db.query('pending_saves', orderBy: 'updated_at ASC');
    return [
      for (final row in rows)
        if (_decode(row['payload']) case final payload?)
          PendingSave(
            kind: row['kind'] as String,
            key: row['key'] as int,
            inspectionId: row['inspection_id'] as int,
            payload: payload,
            updatedAt: DateTime.parse(row['updated_at'] as String),
          ),
    ];
  }

  // --- who the local data belongs to ---

  Future<int?> owner() async {
    final db = await database;
    final rows = await db.query('meta',
        where: 'key = ?', whereArgs: [_ownerKey], limit: 1);
    return rows.isEmpty ? null : int.tryParse(rows.first['value'] as String);
  }

  Future<void> setOwner(int userId) async {
    final db = await database;
    await db.insert('meta', {'key': _ownerKey, 'value': '$userId'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Wipes everything (drafts, unsent edits and the owner).
  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('drafts');
      await txn.delete('pending_saves');
      await txn.delete('meta');
    });
  }

  static Map<String, dynamic>? _decode(Object? raw) {
    try {
      return jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

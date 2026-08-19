import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class LocalDraftStorage {
  Database? _database;

  Future<Database> get database async {
    _database ??= await openDatabase(
      path.join(await getDatabasesPath(), 'inspection_drafts.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE drafts(
            inspection_id INTEGER PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<void> saveDraft(int inspectionId, Map<String, dynamic> payload) async {
    final db = await database;
    await db.insert(
      'drafts',
      {'inspection_id': inspectionId, 'payload': jsonEncode(payload), 'updated_at': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearDraft(int inspectionId) async {
    final db = await database;
    await db.delete('drafts', where: 'inspection_id = ?', whereArgs: [inspectionId]);
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:store_inspection_mobile/drafts/local_draft_storage.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LocalDraftStorage storage;

  setUp(() {
    storage = LocalDraftStorage(databasePath: inMemoryDatabasePath);
  });

  tearDown(() => storage.close());

  group('drafts', () {
    test('a saved inspection can be loaded again', () async {
      await storage.saveDraft(7, {'id': 7, 'status': 'in_progress'});

      expect(await storage.loadDraft(7), {'id': 7, 'status': 'in_progress'});
      expect(await storage.loadDraft(8), isNull);
    });

    test('saving again replaces the copy and the newest is listed first',
        () async {
      await storage.saveDraft(1, {'id': 1, 'v': 1});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await storage.saveDraft(2, {'id': 2});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await storage.saveDraft(1, {'id': 1, 'v': 2});

      final drafts = await storage.loadDrafts();

      expect(drafts.map((draft) => draft['id']), [1, 2]);
      expect(drafts.first['v'], 2);
    });

    test('clearDraft removes only that inspection', () async {
      await storage.saveDraft(1, {'id': 1});
      await storage.saveDraft(2, {'id': 2});

      await storage.clearDraft(1);

      expect(await storage.loadDraft(1), isNull);
      expect(await storage.loadDraft(2), isNotNull);
    });
  });

  group('pending saves', () {
    test('are stored per kind and key, replacing the earlier edit', () async {
      await storage.savePending('response', 1, 7, {'score': 2});
      await storage.savePending('response', 1, 7, {'score': 5});
      await storage.savePending('comment', 7, 7, {'comment': 'hi'});
      // The same number under another kind is a different edit.
      await storage.savePending('comment', 1, 9, {'comment': 'other'});

      final pending = await storage.loadPending();

      expect(pending, hasLength(3));
      final response = pending.singleWhere((p) => p.kind == 'response');
      expect(response.key, 1);
      expect(response.inspectionId, 7);
      expect(response.payload, {'score': 5});
    });

    test('come back oldest first', () async {
      await storage.savePending('response', 1, 7, {'n': 1});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await storage.savePending('response', 2, 7, {'n': 2});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await storage.savePending('response', 3, 7, {'n': 3});

      expect((await storage.loadPending()).map((p) => p.key), [1, 2, 3]);
    });

    test('can be deleted individually', () async {
      await storage.savePending('response', 1, 7, {});
      await storage.savePending('comment', 7, 7, {});

      await storage.deletePending('response', 1);

      expect((await storage.loadPending()).map((p) => p.kind), ['comment']);
    });
  });

  group('owner', () {
    test('is remembered and replaced', () async {
      expect(await storage.owner(), isNull);

      await storage.setOwner(5);
      expect(await storage.owner(), 5);

      await storage.setOwner(6);
      expect(await storage.owner(), 6);
    });

    test('clearAll wipes drafts, unsent edits and the owner', () async {
      await storage.saveDraft(1, {'id': 1});
      await storage.savePending('response', 1, 1, {});
      await storage.setOwner(5);

      await storage.clearAll();

      expect(await storage.loadDrafts(), isEmpty);
      expect(await storage.loadPending(), isEmpty);
      expect(await storage.owner(), isNull);
    });
  });

  test('an existing version 1 database is upgraded without losing drafts',
      () async {
    final directory = await Directory.systemTemp.createTemp('drafts_test');
    addTearDown(() => directory.delete(recursive: true));
    final file = path.join(directory.path, 'old.db');

    // What the previous app version created.
    final old = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE drafts(
            inspection_id INTEGER PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        '''),
      ),
    );
    await old.insert('drafts', {
      'inspection_id': 3,
      'payload': '{"id":3}',
      'updated_at': DateTime.now().toIso8601String(),
    });
    await old.close();

    final upgraded = LocalDraftStorage(databasePath: file);
    addTearDown(upgraded.close);

    expect(await upgraded.loadDraft(3), {'id': 3});
    await upgraded.savePending('response', 1, 3, {'score': 4});
    await upgraded.setOwner(5);
    expect(await upgraded.loadPending(), hasLength(1));
    expect(await upgraded.owner(), 5);
  });
}

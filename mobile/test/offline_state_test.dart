import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/inspections/inspection_state.dart';

import 'support/fakes.dart';

final offline = ApiException('Cannot reach the server', 0);

Map<String, dynamic> inspectionJson({
  int id = 7,
  String status = 'in_progress',
  String comment = '',
}) =>
    {
      'id': id,
      'status': status,
      'score': 60,
      'comment': comment,
      'store': {
        'id': 1,
        'name': 'Downtown',
        'store_code': 'DT',
        'address': 'Main'
      },
      'responses': [
        {
          'id': 1,
          'title': 'Floors',
          'score': 2,
          'not_applicable': false,
          'passed': false,
          'comment': null
        },
        {
          'id': 2,
          'title': 'Counters',
          'score': 3,
          'not_applicable': false,
          'passed': false,
          'comment': null
        },
      ],
    };

void main() {
  late RecordingApiClient api;
  late MemoryDraftStorage storage;
  late InspectionState state;

  /// Runs [body] with a fresh app whose inspection 7 is active.
  void inFakeTime(void Function(FakeAsync async) body) {
    fakeAsync((async) {
      api = RecordingApiClient();
      storage = MemoryDraftStorage();
      state = InspectionState(api, storage)
        ..activeInspection = inspectionJson();
      body(async);
    });
  }

  /// A new [InspectionState] over the same storage, like restarting the app.
  InspectionState restart() =>
      InspectionState(api = RecordingApiClient(), storage);

  void save(int responseId,
          {int score = 4,
          bool passed = false,
          String? comment,
          bool immediate = true}) =>
      state.scheduleResponseSave(responseId,
          score: score,
          notApplicable: false,
          passed: passed,
          comment: comment,
          immediate: immediate);

  group('keeping unsent edits on the device', () {
    test('an edit is stored as soon as it is queued and removed once sent', () {
      inFakeTime((async) {
        save(1, comment: 'wet', immediate: false);

        expect(storage.pending.keys, ['response:1']);
        expect(storage.pending['response:1']!.payload['comment'], 'wet');
        expect(storage.pending['response:1']!.inspectionId, 7);

        async.elapse(InspectionState.responseSaveDelay * 2);
        async.flushMicrotasks();

        expect(api.patchBodies('/inspection_responses/1'), hasLength(1));
        expect(storage.pending, isEmpty);
      });
    });

    test('a newer edit made while sending is not erased by the older save', () {
      inFakeTime((async) {
        final gate = Completer<void>();
        api.holdNextPatch = gate;
        save(1, score: 2);
        async.flushMicrotasks();

        save(1, score: 5);
        async.flushMicrotasks();
        gate.complete();
        async.flushMicrotasks();

        final scores = api
            .patchBodies('/inspection_responses/1')
            .map((body) => body['response']['score']);
        expect(scores, [2, 5]);
        expect(storage.pending, isEmpty);
      });
    });

    test('a failed edit stays stored and is retried by itself', () {
      inFakeTime((async) {
        api.failPatchesWith = offline;
        save(1, passed: true);
        async.flushMicrotasks();

        expect(state.saveError, 'Cannot reach the server');
        expect(state.saveErrorWillRetry, isTrue);
        expect(storage.pending.keys, ['response:1']);

        api.failPatchesWith = null;
        async.elapse(InspectionState.retryInterval);
        async.flushMicrotasks();

        expect(api.patchBodies('/inspection_responses/1'), hasLength(2));
        expect(state.saveError, isNull);
        expect(state.hasPendingSaves, isFalse);
        expect(storage.pending, isEmpty);

        // Nothing left to retry: the timer stops asking the server.
        final requests = api.requests.length;
        async.elapse(InspectionState.retryInterval * 3);
        async.flushMicrotasks();
        expect(api.requests.length, requests);
      });
    });

    test('server trouble (5xx) is retried too', () {
      inFakeTime((async) {
        api.failPatchesWith = ApiException('Request failed (503)', 503);
        save(1);
        async.flushMicrotasks();
        expect(state.saveErrorWillRetry, isTrue);

        api.failPatchesWith = null;
        async.elapse(InspectionState.retryInterval);
        async.flushMicrotasks();

        expect(state.hasPendingSaves, isFalse);
      });
    });

    test('unsent edits are sent after the app is restarted', () {
      inFakeTime((async) {
        api.failPatchesWith = offline;
        save(1, passed: true, comment: 'sticky');
        async.flushMicrotasks();
        state.dispose();

        final relaunched = restart();
        relaunched.attachToUser(5);
        async.flushMicrotasks();

        final saves = api.patchBodies('/inspection_responses/1');
        expect(saves, hasLength(1));
        expect(saves.single['response']['passed'], isTrue);
        expect(saves.single['response']['comment'], 'sticky');
        expect(storage.pending, isEmpty);
        expect(storage.ownerId, 5);
        relaunched.dispose();
      });
    });

    test('the unsent inspection comment survives a restart too', () {
      inFakeTime((async) {
        api.failPatchesWith = offline;
        state.scheduleCommentSave('first draft');
        state.scheduleCommentSave('final words');
        async.elapse(InspectionState.commentSaveDelay * 2);
        async.flushMicrotasks();
        state.dispose();
        expect(storage.pending.keys, ['comment:7']);

        final relaunched = restart();
        relaunched.attachToUser(5);
        async.flushMicrotasks();

        expect(
            api.patchBodies('/inspections/7').single['inspection']['comment'],
            'final words');
        expect(storage.pending, isEmpty);
        relaunched.dispose();
      });
    });

    test('submitting drops the stored comment (it travels with the submit)',
        () {
      inFakeTime((async) {
        api.failPatchesWith = offline;
        state.scheduleCommentSave('note');
        async.flushMicrotasks();
        expect(storage.pending.keys, ['comment:7']);

        api.failPatchesWith = null;
        state.submit('final');
        async.flushMicrotasks();

        expect(storage.pending, isEmpty);
        expect(api.patchBodies('/inspections/7'), isEmpty);
      });
    });
  });

  group('edits that cannot succeed', () {
    test('an inspection that is gone or already submitted drops the edit', () {
      inFakeTime((async) {
        api.failPatchesWith =
            ApiException('submitted inspections cannot be changed', 409);
        save(1);
        async.flushMicrotasks();

        expect(state.saveError, contains('could not be applied'));
        expect(state.saveErrorWillRetry, isFalse);
        expect(state.hasPendingSaves, isFalse);
        expect(storage.pending, isEmpty);

        final requests = api.requests.length;
        async.elapse(InspectionState.retryInterval * 3);
        async.flushMicrotasks();
        expect(api.requests.length, requests);
      });
    });

    test('an invalid edit (422) is kept for the user to fix, not hammered', () {
      inFakeTime((async) {
        api.failPatchesWith = ApiException('Score must be at most 5', 422);
        save(1, score: 9);
        async.flushMicrotasks();

        expect(state.saveError, 'Score must be at most 5');
        expect(state.saveErrorWillRetry, isFalse);
        expect(storage.pending.keys, ['response:1']);

        final requests = api.requests.length;
        async.elapse(InspectionState.retryInterval * 3);
        async.flushMicrotasks();
        expect(api.requests.length, requests);

        // Correcting it clears the problem.
        api.failPatchesWith = null;
        save(1, score: 4);
        async.flushMicrotasks();
        expect(state.saveError, isNull);
        expect(storage.pending, isEmpty);
      });
    });

    test('background retries skip stuck edits but still send the others', () {
      inFakeTime((async) {
        api.failPatchesByPath['/inspection_responses/1'] =
            ApiException('Score must be at most 5', 422);
        api.failPatchesByPath['/inspection_responses/2'] = offline;
        save(1, score: 9);
        save(2);
        async.flushMicrotasks();

        api.failPatchesByPath.remove('/inspection_responses/2');
        async.elapse(InspectionState.retryInterval);
        async.flushMicrotasks();

        expect(api.patchBodies('/inspection_responses/2'), hasLength(2));
        expect(api.patchBodies('/inspection_responses/1'), hasLength(1));
        expect(storage.pending.keys, ['response:1']);
      });
    });
  });

  group('who the local data belongs to', () {
    test('another user\'s leftovers are discarded, not sent', () {
      inFakeTime((async) {
        storage.ownerId = 9;
        storage.drafts[7] = inspectionJson();
        storage.pending['response:1'] = PendingSaveFake.response(1, 7);

        final relaunched = restart();
        relaunched.attachToUser(5);
        async.flushMicrotasks();

        expect(api.requests, isEmpty);
        expect(storage.pending, isEmpty);
        expect(storage.drafts, isEmpty);
        expect(storage.ownerId, 5);
        relaunched.dispose();
      });
    });

    test('the same user keeps their drafts', () {
      inFakeTime((async) {
        storage.ownerId = 5;
        storage.drafts[7] = inspectionJson();

        final relaunched = restart();
        relaunched.attachToUser(5);
        async.flushMicrotasks();

        expect(storage.drafts, isNotEmpty);
        expect(relaunched.localDrafts, hasLength(1));
        relaunched.dispose();
      });
    });
  });

  group('resuming without a connection', () {
    test('uses the copy saved on the device', () {
      inFakeTime((async) {
        storage.drafts[7] = inspectionJson(comment: 'saved note');
        state.activeInspection = null;
        api.failGetsWith = offline;

        state.resumeInspection(7);
        async.flushMicrotasks();

        expect(state.activeInspection!['id'], 7);
        expect(state.activeInspection!['comment'], 'saved note');
      });
    });

    test('shows edits that were never sent on top of the saved copy', () {
      inFakeTime((async) {
        storage.drafts[7] = inspectionJson();
        api.failPatchesWith = offline;
        save(1, score: 5, passed: true, comment: 'fixed');
        state.scheduleCommentSave('my note');
        async.flushMicrotasks();
        state.activeInspection = null;
        api.failGetsWith = offline;

        state.resumeInspection(7);
        async.flushMicrotasks();

        final floors = (state.activeInspection!['responses'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((r) => r['id'] == 1);
        expect(floors['score'], 5);
        expect(floors['passed'], isTrue);
        expect(floors['comment'], 'fixed');
        final counters = (state.activeInspection!['responses'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((r) => r['id'] == 2);
        expect(counters['score'], 3);
        expect(state.activeInspection!['comment'], 'my note');
      });
    });

    test('also overlays unsent edits when the server is reachable', () {
      inFakeTime((async) {
        api.inspectionPayload = inspectionJson();
        api.failPatchesWith = offline;
        save(2, score: 5);
        async.flushMicrotasks();
        state.activeInspection = null;

        state.resumeInspection(7);
        async.flushMicrotasks();

        final counters = (state.activeInspection!['responses'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((r) => r['id'] == 2);
        expect(counters['score'], 5);
      });
    });

    test('without a saved copy the connection error is reported', () {
      inFakeTime((async) {
        state.activeInspection = null;
        api.failGetsWith = offline;

        Object? error;
        state.resumeInspection(7).catchError((Object e) => error = e);
        async.flushMicrotasks();

        expect(error, isA<ApiException>());
      });
    });

    test('a real server answer is never replaced by the saved copy', () {
      inFakeTime((async) {
        storage.drafts[7] = inspectionJson();
        state.activeInspection = null;
        api.failGetsWith = ApiException('not found', 404);

        Object? error;
        state.resumeInspection(7).catchError((Object e) => error = e);
        async.flushMicrotasks();

        expect(error, isA<ApiException>());
        expect(state.activeInspection, isNull);
      });
    });
  });

  group('refreshing the lists', () {
    test('a failure is remembered instead of thrown, and lists are kept', () {
      inFakeTime((async) {
        state.stores = [
          {'id': 1}
        ];
        api.failGetsWith = offline;

        Object? error;
        state.refreshAll().catchError((Object e) => error = e);
        async.flushMicrotasks();

        expect(error, isNull);
        expect(state.loadError, 'Cannot reach the server');
        expect(state.stores, hasLength(1));
      });
    });

    test('recovers when the connection is back', () {
      inFakeTime((async) {
        api.failGetsWith = offline;
        state.refreshAll();
        async.flushMicrotasks();
        expect(state.loadError, isNotNull);

        api.failGetsWith = null;
        state.refreshAll();
        async.flushMicrotasks();

        expect(state.loadError, isNull);
      });
    });

    test('lists only the unfinished inspections saved on the device', () {
      inFakeTime((async) {
        storage.drafts[7] = inspectionJson(id: 7);
        storage.drafts[8] = inspectionJson(id: 8, status: 'submitted');
        storage.drafts[9] = inspectionJson(id: 9, status: 'draft');

        state.refreshAll();
        async.flushMicrotasks();

        expect(state.localDrafts.map((d) => d['id']), unorderedEquals([7, 9]));
      });
    });
  });

  test('reset stops retries and forgets the on-device list', () {
    inFakeTime((async) {
      api.failPatchesWith = offline;
      save(1);
      async.flushMicrotasks();
      state.localDrafts = [inspectionJson()];
      state.loadError = 'x';

      state.reset(clearLocalData: false);
      api.failPatchesWith = null;
      final requests = api.requests.length;
      async.elapse(InspectionState.retryInterval * 3);
      async.flushMicrotasks();

      expect(api.requests.length, requests);
      expect(state.localDrafts, isEmpty);
      expect(state.loadError, isNull);
      // The unsent edit is still on the device for the same user's next login.
      expect(storage.pending.keys, ['response:1']);
    });
  });

  group('a local store that stops answering', () {
    void withHangingStore(void Function(FakeAsync async) body) {
      fakeAsync((async) {
        api = RecordingApiClient()
          ..inspectionPayload = inspectionJson(comment: 'from server');
        storage = HangingDraftStorage();
        state = InspectionState(api, storage)
          ..activeInspection = inspectionJson();
        body(async);
      });
    }

    test('never holds up saving to the server or updating the screen', () {
      withHangingStore((async) {
        var notified = 0;
        state.addListener(() => notified++);

        save(1, score: 5);
        async.flushMicrotasks();

        expect(api.patchBodies('/inspection_responses/1'), hasLength(1));
        expect(state.hasPendingSaves, isFalse);
        // The reload after the save reached the screen without waiting for the
        // local copy to be written.
        expect(state.activeInspection!['comment'], 'from server');
        expect(notified, greaterThan(0));
      });
    });

    test('does not stop a second save from being sent', () {
      withHangingStore((async) {
        save(1, score: 2);
        async.flushMicrotasks();
        save(1, score: 5);
        async.flushMicrotasks();

        final scores = api
            .patchBodies('/inspection_responses/1')
            .map((body) => body['response']['score']);
        expect(scores, [2, 5]);
      });
    });

    test('does not stop an inspection from being submitted', () {
      withHangingStore((async) {
        Object? error;
        var finished = false;
        state.submit('done').then((_) => finished = true, onError: (Object e) {
          error = e;
        });
        async.elapse(InspectionState.localStoreTimeout * 2);
        async.flushMicrotasks();

        expect(error, isNull);
        expect(finished, isTrue, reason: 'submit returned');
        expect(api.requests, contains('POST /inspections/7/submit'));
        expect(state.activeInspection!['status'], 'submitted');
      });
    });

    test('signing in is not held up forever', () {
      withHangingStore((async) {
        var finished = false;
        state.attachToUser(5).then((_) => finished = true);
        async.flushMicrotasks();
        expect(finished, isFalse);

        async.elapse(InspectionState.localStoreTimeout * 3);
        async.flushMicrotasks();

        expect(finished, isTrue);
      });
    });

    test(
        'offline resume gives up on a stuck local copy with the original error',
        () {
      withHangingStore((async) {
        state.activeInspection = null;
        api.failGetsWith = offline;

        Object? error;
        state.resumeInspection(7).catchError((Object e) => error = e);
        async.elapse(InspectionState.localStoreTimeout * 2);
        async.flushMicrotasks();

        expect(error, isA<ApiException>());
      });
    });
  });
}

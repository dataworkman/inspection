import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/inspections/inspection_state.dart';

import 'support/fakes.dart';

void main() {
  late RecordingApiClient api;
  late InspectionState state;

  void scheduleResponse({
    int score = 4,
    bool passed = false,
    String? comment,
    bool immediate = false,
  }) =>
      state.scheduleResponseSave(
        1,
        score: score,
        notApplicable: false,
        passed: passed,
        comment: comment,
        immediate: immediate,
      );

  void inFakeTime(void Function(FakeAsync async) body) {
    fakeAsync((async) {
      api = RecordingApiClient();
      state = InspectionState(api, NoDraftStorage())
        ..activeInspection = {'id': 7, 'responses': []};
      body(async);
    });
  }

  test('typing is debounced into a single save with the latest text', () {
    inFakeTime((async) {
      scheduleResponse(comment: 'a');
      async.elapse(const Duration(milliseconds: 300));
      scheduleResponse(comment: 'ab');
      async.elapse(const Duration(milliseconds: 300));
      scheduleResponse(comment: 'abc');
      async.elapse(const Duration(milliseconds: 600));
      expect(api.requests, isEmpty);

      async.elapse(const Duration(milliseconds: 200));
      async.flushMicrotasks();

      final saves = api.patchBodies('/inspection_responses/1');
      expect(saves, hasLength(1));
      expect(saves.single['response']['comment'], 'abc');
    });
  });

  test('toggling Pass is sent immediately', () {
    inFakeTime((async) {
      scheduleResponse(passed: true, immediate: true);
      async.flushMicrotasks();

      final saves = api.patchBodies('/inspection_responses/1');
      expect(saves, hasLength(1));
      expect(saves.single['response']['passed'], isTrue);
    });
  });

  test('a later edit replaces the queued one so nothing is lost', () {
    inFakeTime((async) {
      scheduleResponse(comment: 'typed but not saved yet');
      scheduleResponse(
          comment: 'typed but not saved yet', passed: true, immediate: true);
      async.elapse(InspectionState.responseSaveDelay * 2);
      async.flushMicrotasks();

      final saves = api.patchBodies('/inspection_responses/1');
      expect(saves, hasLength(1));
      expect(saves.single['response']['passed'], isTrue);
      expect(saves.single['response']['comment'], 'typed but not saved yet');
    });
  });

  test('saves for one response reach the server in order', () {
    inFakeTime((async) {
      final gate = Completer<void>();
      api.holdNextPatch = gate;
      scheduleResponse(score: 2, immediate: true);
      async.flushMicrotasks();
      scheduleResponse(score: 5, immediate: true);
      async.flushMicrotasks();

      // The second save waits for the first one to finish.
      expect(api.patchBodies('/inspection_responses/1'), hasLength(1));

      gate.complete();
      async.flushMicrotasks();

      final scores = api
          .patchBodies('/inspection_responses/1')
          .map((body) => body['response']['score'])
          .toList();
      expect(scores, [2, 5]);
    });
  });

  test('submit sends unsaved edits first, then the submit request', () {
    inFakeTime((async) {
      scheduleResponse(comment: 'still typing');

      Object? error;
      state.submit('final comment').catchError((Object e) => error = e);
      async.flushMicrotasks();

      expect(error, isNull);
      final firstPatch = api.requests.indexOf('PATCH /inspection_responses/1');
      final submit = api.requests.indexOf('POST /inspections/7/submit');
      expect(firstPatch, isNonNegative);
      expect(submit, greaterThan(firstPatch));
      expect(
          api.patchBodies('/inspection_responses/1').single['response']
              ['comment'],
          'still typing');
      expect(state.activeInspection!['status'], 'submitted');
    });
  });

  test('the final comment is not autosaved separately when submitting', () {
    inFakeTime((async) {
      state.scheduleCommentSave('final comment');
      state.submit('final comment');
      async.elapse(InspectionState.commentSaveDelay * 2);
      async.flushMicrotasks();

      expect(api.patchBodies('/inspections/7'), isEmpty);
      final submitIndex = api.requests.indexOf('POST /inspections/7/submit');
      expect(api.bodies[submitIndex]['inspection']['comment'], 'final comment');
    });
  });

  test('the inspection comment is debounced too', () {
    inFakeTime((async) {
      for (final text in ['h', 'he', 'hey']) {
        state.scheduleCommentSave(text);
        async.elapse(const Duration(milliseconds: 200));
      }
      expect(api.requests, isEmpty);

      async.elapse(InspectionState.commentSaveDelay);
      async.flushMicrotasks();

      final saves = api.patchBodies('/inspections/7');
      expect(saves, hasLength(1));
      expect(saves.single['inspection']['comment'], 'hey');
    });
  });

  test('a failed save keeps the edit, blocks submit and is retried', () {
    inFakeTime((async) {
      api.failPatchesWith = ApiException('Network down', 0);
      scheduleResponse(passed: true, immediate: true);
      async.flushMicrotasks();
      expect(state.saveError, 'Network down');

      Object? error;
      state.submit('done').catchError((Object e) => error = e);
      async.flushMicrotasks();

      expect(error, isA<ApiException>());
      expect(error.toString(), contains('Could not save your latest changes'));
      expect(api.requests, isNot(contains('POST /inspections/7/submit')));

      api.failPatchesWith = null;
      Object? retryError;
      state.submit('done').catchError((Object e) => retryError = e);
      async.flushMicrotasks();

      expect(retryError, isNull);
      expect(state.saveError, isNull);
      expect(
          api.patchBodies('/inspection_responses/1').last['response']['passed'],
          isTrue);
      expect(api.requests, contains('POST /inspections/7/submit'));
    });
  });

  test('a save finishing after the user moved on does not switch inspections',
      () {
    inFakeTime((async) {
      scheduleResponse(passed: true, immediate: true);
      state.activeInspection = {'id': 8, 'responses': []};
      async.flushMicrotasks();

      expect(api.requests, ['PATCH /inspection_responses/1']);
      expect(state.activeInspection!['id'], 8);
    });
  });

  group('reset', () {
    late NoDraftStorage drafts;

    void inFakeTimeWithDrafts(void Function(FakeAsync async) body) {
      fakeAsync((async) {
        api = RecordingApiClient();
        drafts = NoDraftStorage();
        state = InspectionState(api, drafts)
          ..activeInspection = {'id': 7, 'responses': []}
          ..stores = [
            {'id': 1}
          ]
          ..templates = [
            {'id': 2}
          ]
          ..history = [
            {'id': 3}
          ]
          ..actions = [
            {'id': 4}
          ]
          ..dashboard = {'submitted_inspections': 1};
        body(async);
      });
    }

    test('forgets the previous user\'s data', () {
      inFakeTimeWithDrafts((async) {
        state.reset();

        expect(state.stores, isEmpty);
        expect(state.templates, isEmpty);
        expect(state.history, isEmpty);
        expect(state.actions, isEmpty);
        expect(state.dashboard, isNull);
        expect(state.activeInspection, isNull);
        expect(state.saveError, isNull);
      });
    });

    test('queued edits are dropped and their timers never fire', () {
      inFakeTimeWithDrafts((async) {
        scheduleResponse(comment: 'typing');
        state.scheduleCommentSave('note');
        expect(state.hasPendingSaves, isTrue);

        state.reset();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        expect(api.requests, isEmpty);
        expect(state.hasPendingSaves, isFalse);
      });
    });

    test('wipes saved drafts on logout but keeps them when the session expired',
        () {
      inFakeTimeWithDrafts((async) {
        state.reset(clearLocalData: false);
        expect(drafts.clearAllCalls, 0);

        state.reset(clearLocalData: true);
        expect(drafts.clearAllCalls, 1);
      });
    });

    test('a save still in flight cannot bring old edits back afterwards', () {
      inFakeTimeWithDrafts((async) {
        final gate = Completer<void>();
        api.holdNextPatch = gate;
        scheduleResponse(passed: true, immediate: true);
        async.flushMicrotasks();

        state.reset();
        api.failPatchesWith = ApiException('Cannot reach the server', 0);
        gate.complete();
        async.flushMicrotasks();

        expect(state.saveError, isNull);
        expect(state.hasPendingSaves, isFalse);
      });
    });
  });

  test('hasPendingSaves reflects queued and failed edits', () {
    inFakeTime((async) {
      expect(state.hasPendingSaves, isFalse);

      scheduleResponse(comment: 'typing');
      expect(state.hasPendingSaves, isTrue);

      async.elapse(InspectionState.responseSaveDelay * 2);
      async.flushMicrotasks();
      expect(state.hasPendingSaves, isFalse);

      api.failPatchesWith = ApiException('Cannot reach the server', 0);
      scheduleResponse(comment: 'again', immediate: true);
      async.flushMicrotasks();
      expect(state.hasPendingSaves, isTrue);
    });
  });
}

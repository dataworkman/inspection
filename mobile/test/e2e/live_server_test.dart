// End-to-end check of the app's real client code against a running backend.
//
//   cd backend && bin/rails db:seed && bin/rails server -p 3002
//   cd mobile && E2E_BASE_URL=http://127.0.0.1:3002 flutter test test/e2e
//
// It uses the demo accounts from db/seeds.rb and creates its own store, so it
// can be run repeatedly. Login is rate limited per account (8 per 15 minutes),
// and this test logs in once per account per run.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/auth/auth_state.dart';
import 'package:store_inspection_mobile/inspections/inspection_state.dart';

import '../support/fakes.dart';

final baseUrl = Platform.environment['E2E_BASE_URL'];
final skipReason =
    baseUrl == null ? 'Set E2E_BASE_URL to run against a live backend' : null;
const password = 'password123';

/// One signed-in device: its own client, auth state, inspection state and
/// local storage, like a separate installation of the app.
class Device {
  Device({String? token})
      : api = ApiClient(baseUrl: baseUrl!, token: token),
        storage = MemoryDraftStorage() {
    state = InspectionState(api, storage);
    auth = AuthState(
      api,
      onSignedIn: state.attachToUser,
      onSignedOut: ({required sessionExpired}) {
        signedOut.add(sessionExpired ? 'expired' : 'logout');
        state.reset(clearLocalData: !sessionExpired);
      },
    );
  }

  final ApiClient api;
  final MemoryDraftStorage storage;
  late final InspectionState state;
  late final AuthState auth;
  final signedOut = <String>[];

  Future<void> login(String email) async {
    SharedPreferences.setMockInitialValues({});
    await auth.login(email, password);
  }
}

Map<String, dynamic> _map(Object? value) => value as Map<String, dynamic>;
List<Map<String, dynamic>> _list(Object? value) =>
    (value as List<dynamic>).cast<Map<String, dynamic>>();

void main() {
  late Device inspector;
  late Device admin;
  late Device manager;
  late int storeId;
  late int templateId;
  late int inspectionId;
  late int actionId;
  late String inspectorToken;
  final stamp = DateTime.now().millisecondsSinceEpoch;

  test('the inspector signs in and the session can be restored', () async {
    inspector = Device();
    await inspector.login('inspector@bakery-inspection.test');

    expect(inspector.auth.signedIn, isTrue);
    expect(inspector.auth.role, 'inspector');
    expect(inspector.auth.userId, isA<int>());
    inspectorToken = inspector.api.token!;

    // A restart: same stored token, new process.
    final prefs = {
      'api_token': inspectorToken,
      'user': jsonEncode(inspector.auth.user),
    };
    SharedPreferences.setMockInitialValues(prefs);
    final relaunched = Device();
    await relaunched.auth.restore();
    expect(relaunched.auth.signedIn, isTrue);
    expect(relaunched.auth.userId, inspector.auth.userId);
  }, skip: skipReason);

  test('the admin creates a store for this run', () async {
    admin = Device();
    await admin.login('admin@bakery-inspection.test');
    expect(admin.auth.isAdmin, isTrue);

    final created = _map((await admin.api.post('/stores', {
      'store': {
        'name': 'E2E Store $stamp',
        'store_code': 'E2E-$stamp',
        'address': '1 Test Way',
      },
    }))['store']);
    storeId = created['id'] as int;
    expect(created['name'], 'E2E Store $stamp');
  }, skip: skipReason);

  test('the lists load and have the shape the screens expect', () async {
    await inspector.state.refreshAll();
    final state = inspector.state;

    expect(state.loadError, isNull);
    final store = state.stores
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['id'] == storeId);
    expect(store.keys, containsAll(['id', 'name', 'store_code', 'address']));
    expect(state.templates, isNotEmpty);
    templateId = _map(state.templates.first)['id'] as int;
    expect(state.openInspectionFor(storeId, inspector.auth.userId), isNull);
  }, skip: skipReason);

  test('starting an inspection returns the checklist the screen renders',
      () async {
    final state = inspector.state;
    await state.startInspection(storeId, templateId);

    final inspection = state.activeInspection!;
    inspectionId = inspection['id'] as int;
    expect(inspection['status'], 'in_progress');
    expect(_map(inspection['store'])['name'], 'E2E Store $stamp');

    final responses = _list(inspection['responses']);
    expect(responses, hasLength(20));
    for (final response in responses) {
      expect(
          response.keys,
          containsAll([
            'id',
            'inspection_question_id',
            'title',
            'category',
            'category_position',
            'position',
            'score',
            'max_score',
            'not_applicable',
            'passed',
            'comment',
            'photos',
          ]));
      expect(response['score'], 0, reason: 'unanswered starts at 0');
    }
    final categories = responses.map((r) => r['category']).toSet();
    expect(
        categories, {'Cleanliness', 'Product Quality', 'Service', 'Facility'});
    expect(inspector.storage.drafts, contains(inspectionId));
  }, skip: skipReason);

  test('submitting with nothing answered is refused with a readable message',
      () async {
    await expectLater(
      inspector.state.submit('too early'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 422)
          .having(
              (e) => e.message, 'message', contains('Answer required items'))),
    );
    expect(inspector.state.activeInspection!['status'], 'in_progress');
  }, skip: skipReason);

  test('answers are saved as they are made and the score follows', () async {
    final state = inspector.state;
    final template = _map((await inspector.api
        .get('/inspection_templates/$templateId'))['inspection_template']);
    final questions = {
      for (final category in _list(template['categories']))
        for (final question in _list(category['questions']))
          question['id'] as int: question,
    };

    for (final response in _list(state.activeInspection!['responses'])) {
      final question = questions[response['inspection_question_id']]!;
      state.scheduleResponseSave(
        response['id'] as int,
        score: 4,
        notApplicable: false,
        passed: true,
        comment: question['comment_required'] == true ? 'Checked, fine.' : null,
        immediate: true,
      );
    }
    await state.flushPendingSaves();

    expect(state.hasPendingSaves, isFalse);
    expect(state.saveError, isNull);
    expect(state.activeInspection!['score'], 80);
    for (final response in _list(state.activeInspection!['responses'])) {
      expect(response['score'], 4);
      expect(response['passed'], isTrue);
    }
    expect(inspector.storage.pending, isEmpty, reason: 'nothing left unsent');
  }, skip: skipReason);

  test('required photos can be attached and the images are served', () async {
    final state = inspector.state;
    final template = _map((await inspector.api
        .get('/inspection_templates/$templateId'))['inspection_template']);
    final needPhoto = {
      for (final category in _list(template['categories']))
        for (final question in _list(category['questions']))
          if (question['photo_required'] == true) question['id'],
    };
    expect(needPhoto, isNotEmpty);

    final photo = XFile.fromData(FakePhotoPicker.onePixelPng,
        name: 'photo.png', mimeType: 'image/png');
    for (final response in _list(state.activeInspection!['responses'])) {
      if (!needPhoto.contains(response['inspection_question_id'])) continue;
      await state.uploadPhoto(
        file: photo,
        responseId: response['id'] as int,
        annotationJson: '{"marks":[]}',
        comment: 'Field photo',
      );
    }

    final withPhotos = _list(state.activeInspection!['responses'])
        .where((r) => (r['photos'] as List).isNotEmpty)
        .toList();
    expect(withPhotos, hasLength(needPhoto.length));
    final firstPhoto = _map((withPhotos.first['photos'] as List).first);
    expect(firstPhoto['original_image_url'], isNotNull);

    // The screens load the image from this URL without any auth header.
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client
        .getUrl(Uri.parse('$baseUrl${firstPhoto['original_image_url']}'));
    request.followRedirects = true;
    final response = await request.close();
    final bytes = await response.expand((chunk) => chunk).toList();
    expect(response.statusCode, 200);
    expect(bytes, FakePhotoPicker.onePixelPng);
  }, skip: skipReason);

  test('a corrective action is created for an item', () async {
    final state = inspector.state;
    final responseId =
        _list(state.activeInspection!['responses']).first['id'] as int;

    final created = await state.createAction(
      responseId,
      title: 'Re-mop the floor',
      severity: 'High',
      dueDate: DateTime.now().add(const Duration(days: 3)),
    );
    actionId = created['id'] as int;

    expect(created['inspection_response_id'], responseId);
    expect(created['status'], 'Open');
    expect(created['due_date'], isNotNull);
    expect(state.actionsForResponse(responseId), hasLength(1));

    await state.loadActions();
    expect(state.actionsForResponse(responseId), hasLength(1),
        reason: 'still there after reloading from the server');
  }, skip: skipReason);

  test('submitting scores the inspection and locks it', () async {
    final state = inspector.state;
    await state.submit('All good');

    final inspection = state.activeInspection!;
    expect(inspection['status'], 'submitted');
    expect(inspection['score'], 80);
    expect(inspection['grade'], 'Good');
    expect(inspector.storage.drafts, isNot(contains(inspectionId)));
    expect(
        state.history
            .cast<Map<String, dynamic>>()
            .firstWhere((h) => h['id'] == inspectionId)['status'],
        'submitted');

    // Late edits are rejected and dropped instead of blocking the user.
    final responseId = _list(inspection['responses']).first['id'] as int;
    state.scheduleResponseSave(responseId,
        score: 1, notApplicable: false, passed: false, immediate: true);
    await expectLater(
        state.flushPendingSaves(),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
    expect(state.saveError, contains('could not be applied'));
    expect(state.hasPendingSaves, isFalse);

    // The read-only result is what the result screen shows.
    final detail = await state.loadInspectionDetail(inspectionId);
    expect(detail['score'], 80);
    expect(_list(detail['responses']).every((r) => r['score'] == 4), isTrue);
  }, skip: skipReason);

  test('an unfinished inspection can be found, resumed and continued offline',
      () async {
    final state = inspector.state;
    await state.startInspection(storeId, templateId);
    final unfinishedId = state.activeInspection!['id'] as int;
    state.scheduleCommentSave('note in progress');
    await state.flushPendingSaves();
    await state.loadHistory();

    final open = state.openInspectionFor(storeId, inspector.auth.userId);
    expect(open, isNotNull);
    expect(open!['id'], unfinishedId);

    // Another device resumes it from the server.
    final tablet = Device(token: inspectorToken);
    await tablet.state.resumeInspection(unfinishedId);
    expect(tablet.state.activeInspection!['comment'], 'note in progress');

    // Then the connection drops: the local copy is used.
    final dead = ApiClient(baseUrl: 'http://127.0.0.1:1');
    await expectLater(
        dead.get('/stores'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'offline', isTrue)));
    final offline = InspectionState(dead, tablet.storage);
    await offline.resumeInspection(unfinishedId);
    expect(offline.activeInspection!['comment'], 'note in progress');
    expect(_list(offline.activeInspection!['responses']), hasLength(20));

    // An edit made offline is kept and sent once the server is reachable.
    final responseId =
        _list(offline.activeInspection!['responses']).first['id'] as int;
    offline.scheduleResponseSave(responseId,
        score: 5, notApplicable: false, passed: true, immediate: true);
    await expectLater(
        offline.flushPendingSaves(), throwsA(isA<ApiException>()));
    expect(offline.saveErrorWillRetry, isTrue);
    expect(tablet.storage.pending, hasLength(1));

    final backOnline = InspectionState(tablet.api, tablet.storage);
    await backOnline.attachToUser(inspector.auth.userId!);
    await backOnline.flushPendingSaves();
    expect(tablet.storage.pending, isEmpty);
    await backOnline.resumeInspection(unfinishedId);
    final saved = _list(backOnline.activeInspection!['responses'])
        .firstWhere((r) => r['id'] == responseId);
    expect(saved['score'], 5);
    expect(saved['passed'], isTrue);
    offline.reset(clearLocalData: false);
  }, skip: skipReason);

  test('the admin dashboard has the shape the screen expects', () async {
    await admin.state.refreshAll(includeDashboard: true);
    final dashboard = admin.state.dashboard!;

    expect(admin.state.loadError, isNull);
    expect(
        dashboard.keys,
        containsAll([
          'average_inspection_score',
          'submitted_inspections',
          'open_corrective_actions',
          'critical_corrective_actions',
          'attention_required',
          'store_ranking',
        ]));
    final row = _list(dashboard['store_ranking'])
        .firstWhere((r) => _map(r['store'])['id'] == storeId);
    expect(
        row.keys,
        containsAll([
          'latest_score',
          'average_score',
          'submitted_inspections',
          'open_issues'
        ]));
    expect(row['latest_score'], 80);
    expect(row['open_issues'], 1);

    // The admin sees the inspector's action and can verify it.
    expect(admin.state.actions.cast<Map<String, dynamic>>().map((a) => a['id']),
        contains(actionId));
    await admin.state.updateActionStatus(actionId, 'In Progress');
    expect(
        admin.state.actions
            .cast<Map<String, dynamic>>()
            .firstWhere((a) => a['id'] == actionId)['status'],
        'In Progress');
  }, skip: skipReason);

  test('a store manager only sees and moves what is assigned to them',
      () async {
    manager = Device();
    await manager.login('manager@bakery-inspection.test');
    await manager.state.refreshAll();

    expect(
        manager.state.actions.cast<Map<String, dynamic>>().map((a) => a['id']),
        isNot(contains(actionId)));
    await expectLater(
      manager.state.startInspection(storeId, templateId),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );

    await admin.api.patch('/corrective_actions/$actionId', {
      'corrective_action': {'assigned_to_id': manager.auth.userId},
    });
    await manager.state.loadActions();
    expect(
        manager.state.actions.cast<Map<String, dynamic>>().map((a) => a['id']),
        contains(actionId));

    await expectLater(
      manager.state.updateActionStatus(actionId, 'Verified'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
    await manager.state.updateActionStatus(actionId, 'Resolved');
    final action = manager.state.actions
        .cast<Map<String, dynamic>>()
        .firstWhere((a) => a['id'] == actionId);
    expect(action['status'], 'Resolved');
    expect(action['completed_at'], isNotNull);
  }, skip: skipReason);

  test('logging out revokes the token, so a restored session is rejected',
      () async {
    final userJson = jsonEncode(inspector.auth.user);
    await inspector.auth.logout();
    expect(inspector.auth.signedIn, isFalse);
    expect(inspector.signedOut, ['logout']);

    await expectLater(
      ApiClient(baseUrl: baseUrl!, token: inspectorToken).get('/me'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );

    // The other device still holds that (now revoked) token.
    SharedPreferences.setMockInitialValues(
        {'api_token': inspectorToken, 'user': userJson});
    final stale = Device();
    await stale.auth.restore();
    // The sign-out callback runs right after restore() returns.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(stale.auth.signedIn, isFalse);
    expect(stale.auth.notice, contains('session expired'));
    expect(stale.signedOut, ['expired']);
  }, skip: skipReason);

  test('a wrong password is an ordinary failed login, not an expired session',
      () async {
    final device = Device();
    SharedPreferences.setMockInitialValues({});

    await expectLater(
      device.auth.login('inspector@bakery-inspection.test', 'wrong-password'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 401)
          .having((e) => e.message, 'message', 'invalid email or password')),
    );
    expect(device.signedOut, isEmpty);
    expect(device.auth.notice, isNull);
  }, skip: skipReason);
}

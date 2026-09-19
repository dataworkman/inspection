import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/photos/photo_picker_service.dart';
import 'package:store_inspection_mobile/drafts/local_draft_storage.dart';

class RecordingApiClient extends ApiClient {
  RecordingApiClient() : super(baseUrl: 'http://example.test');

  /// Every request in the order it reached the "server", e.g. `PATCH /inspection_responses/1`.
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];

  /// Photo uploads that reached the "server".
  final uploads =
      <({int responseId, bool annotated, String? annotationJson})>[];

  /// Corrective actions the "server" holds (GET /corrective_actions).
  List<Map<String, dynamic>> actionsPayload = [];
  Object? failPostsWith;
  Object? failGetsWith;
  Completer<void>? holdNextPost;

  /// What GET /inspections (the history list) returns.
  List<Map<String, dynamic>> historyPayload = [];

  /// What GET /inspections/:id returns.
  Map<String, dynamic> inspectionPayload = {'id': 7, 'responses': []};
  Object? failPatchesWith;
  final failPatchesByPath = <String, Object>{};
  Completer<void>? holdNextPatch;

  List<Map<String, dynamic>> patchBodies(String path) => [
        for (var i = 0; i < requests.length; i++)
          if (requests[i] == 'PATCH $path') bodies[i],
      ];

  @override
  Future<Map<String, dynamic>> get(String path) async {
    requests.add('GET $path');
    bodies.add(const {});
    if (failGetsWith != null) throw failGetsWith!;
    if (path == '/inspections') return {'inspections': historyPayload};
    if (path == '/stores') return {'stores': []};
    if (path == '/inspection_templates') return {'inspection_templates': []};
    if (path == '/corrective_actions') {
      return {'corrective_actions': actionsPayload};
    }
    return {'inspection': inspectionPayload};
  }

  Object? failDeletesWith;

  @override
  Future<Map<String, dynamic>> delete(String path) async {
    requests.add('DELETE $path');
    bodies.add(const {});
    if (failDeletesWith != null) throw failDeletesWith!;
    return {};
  }

  @override
  Future<Map<String, dynamic>> patch(
      String path, Map<String, dynamic> body) async {
    requests.add('PATCH $path');
    bodies.add(body);
    final hold = holdNextPatch;
    holdNextPatch = null;
    if (hold != null) await hold.future;
    final failure = failPatchesByPath[path] ?? failPatchesWith;
    if (failure != null) throw failure;
    final actionMatch = RegExp(r'^/corrective_actions/(\d+)$').firstMatch(path);
    if (actionMatch != null) {
      final id = int.parse(actionMatch.group(1)!);
      final index = actionsPayload.indexWhere((action) => action['id'] == id);
      actionsPayload[index] = {
        ...actionsPayload[index],
        ...(body['corrective_action'] as Map<String, dynamic>),
      };
      return {'corrective_action': actionsPayload[index]};
    }
    return {
      'inspection': {'id': 7, 'responses': []},
    };
  }

  @override
  Future<Map<String, dynamic>> uploadPhoto({
    required XFile file,
    XFile? annotatedFile,
    required int responseId,
    String? annotationJson,
    String? comment,
  }) async {
    requests.add('UPLOAD /inspection_responses/$responseId/photos');
    bodies.add(const {});
    uploads.add((
      responseId: responseId,
      annotated: annotatedFile != null,
      annotationJson: annotationJson,
    ));
    return {
      'photo': {'id': 1},
    };
  }

  @override
  Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body) async {
    requests.add('POST $path');
    bodies.add(body);
    final hold = holdNextPost;
    holdNextPost = null;
    if (hold != null) await hold.future;
    if (failPostsWith != null) throw failPostsWith!;
    if (path == '/inspections') return {'inspection': inspectionPayload};
    if (path == '/corrective_actions') {
      final input = body['corrective_action'] as Map<String, dynamic>;
      final created = {
        'id': actionsPayload.length + 100,
        ...input,
        'store': {'name': 'Downtown'},
      };
      actionsPayload.insert(0, created);
      return {'corrective_action': created};
    }
    return {
      'inspection': {'id': 7, 'status': 'submitted'},
    };
  }
}

/// A working in-memory stand-in for [LocalDraftStorage]. Keep one instance
/// across two [InspectionState]s to simulate the app being restarted.
class MemoryDraftStorage extends LocalDraftStorage {
  int clearAllCalls = 0;
  final drafts = <int, Map<String, dynamic>>{};
  final pending = <String, PendingSave>{};
  int? ownerId;

  @override
  Future<void> saveDraft(
          int inspectionId, Map<String, dynamic> payload) async =>
      drafts[inspectionId] = payload;

  @override
  Future<Map<String, dynamic>?> loadDraft(int inspectionId) async =>
      drafts[inspectionId];

  @override
  Future<List<Map<String, dynamic>>> loadDrafts() async =>
      drafts.values.toList().reversed.toList();

  @override
  Future<void> clearDraft(int inspectionId) async =>
      drafts.remove(inspectionId);

  @override
  Future<void> savePending(String kind, int key, int inspectionId,
      Map<String, dynamic> payload) async {
    // Re-inserting moves the entry to the end, like an updated_at ordering.
    pending.remove('$kind:$key');
    pending['$kind:$key'] = PendingSave(
      kind: kind,
      key: key,
      inspectionId: inspectionId,
      payload: payload,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deletePending(String kind, int key) async =>
      pending.remove('$kind:$key');

  @override
  Future<List<PendingSave>> loadPending() async => pending.values.toList();

  @override
  Future<int?> owner() async => ownerId;

  @override
  Future<void> setOwner(int userId) async => ownerId = userId;

  @override
  Future<void> clearAll() async {
    clearAllCalls++;
    drafts.clear();
    pending.clear();
    ownerId = null;
  }
}

typedef NoDraftStorage = MemoryDraftStorage;

/// Returns a 1x1 PNG instead of opening the camera or gallery.
class FakePhotoPicker extends PhotoPickerService {
  static final onePixelPng = Uint8List.fromList(const [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
    0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f,
    0x00, 0x05, 0xfe, 0x02, 0xfe, 0xa7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
    0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
  ]);

  XFile? _photo() =>
      XFile.fromData(onePixelPng, name: 'photo.png', mimeType: 'image/png');

  @override
  Future<XFile?> takePhoto() async => _photo();

  @override
  Future<XFile?> choosePhoto() async => _photo();
}

/// Builds stored edits for tests that need to pre-fill the storage.
class PendingSaveFake {
  static PendingSave response(int responseId, int inspectionId) => PendingSave(
        kind: 'response',
        key: responseId,
        inspectionId: inspectionId,
        payload: const {
          'score': 4,
          'not_applicable': false,
          'passed': false,
          'comment': null,
        },
        updatedAt: DateTime(2026, 1, 1),
      );
}

/// A local store that never answers, like a stuck IndexedDB/SQLite worker.
class HangingDraftStorage extends MemoryDraftStorage {
  Future<T> _never<T>() => Completer<T>().future;

  @override
  Future<void> saveDraft(int inspectionId, Map<String, dynamic> payload) =>
      _never();

  @override
  Future<Map<String, dynamic>?> loadDraft(int inspectionId) => _never();

  @override
  Future<List<Map<String, dynamic>>> loadDrafts() => _never();

  @override
  Future<void> clearDraft(int inspectionId) => _never();

  @override
  Future<void> savePending(String kind, int key, int inspectionId,
          Map<String, dynamic> payload) =>
      _never();

  @override
  Future<void> deletePending(String kind, int key) => _never();

  @override
  Future<List<PendingSave>> loadPending() => _never();

  @override
  Future<int?> owner() => _never();

  @override
  Future<void> setOwner(int userId) => _never();

  @override
  Future<void> clearAll() => _never();
}

import 'dart:async';

import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/drafts/local_draft_storage.dart';

class RecordingApiClient extends ApiClient {
  RecordingApiClient() : super(baseUrl: 'http://example.test');

  /// Every request in the order it reached the "server", e.g. `PATCH /inspection_responses/1`.
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];
  Object? failPatchesWith;
  Completer<void>? holdNextPatch;

  List<Map<String, dynamic>> patchBodies(String path) => [
        for (var i = 0; i < requests.length; i++)
          if (requests[i] == 'PATCH $path') bodies[i],
      ];

  @override
  Future<Map<String, dynamic>> get(String path) async {
    requests.add('GET $path');
    bodies.add(const {});
    if (path == '/inspections') return {'inspections': []};
    return {
      'inspection': {'id': 7, 'responses': []},
    };
  }

  @override
  Future<Map<String, dynamic>> patch(
      String path, Map<String, dynamic> body) async {
    requests.add('PATCH $path');
    bodies.add(body);
    final hold = holdNextPatch;
    holdNextPatch = null;
    if (hold != null) await hold.future;
    if (failPatchesWith != null) throw failPatchesWith!;
    return {
      'inspection': {'id': 7, 'responses': []},
    };
  }

  @override
  Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body) async {
    requests.add('POST $path');
    bodies.add(body);
    return {
      'inspection': {'id': 7, 'status': 'submitted'},
    };
  }
}

class NoDraftStorage extends LocalDraftStorage {
  @override
  Future<void> saveDraft(
      int inspectionId, Map<String, dynamic> payload) async {}

  @override
  Future<void> clearDraft(int inspectionId) async {}
}

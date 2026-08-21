import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../drafts/local_draft_storage.dart';

class InspectionState extends ChangeNotifier {
  InspectionState(this.apiClient, this.drafts);

  final ApiClient apiClient;
  final LocalDraftStorage drafts;

  List<dynamic> stores = [];
  List<dynamic> templates = [];
  List<dynamic> history = [];
  List<dynamic> actions = [];
  Map<String, dynamic>? dashboard;
  Map<String, dynamic>? activeInspection;

  Future<void> loadStores() async {
    stores = (await apiClient.get('/stores'))['stores'] as List<dynamic>;
    notifyListeners();
  }

  Future<void> loadTemplates() async {
    templates = (await apiClient
        .get('/inspection_templates'))['inspection_templates'] as List<dynamic>;
    notifyListeners();
  }

  Future<void> startInspection(int storeId, int templateId) async {
    final payload = await apiClient.post('/inspections', {
      'inspection': {
        'store_id': storeId,
        'inspection_template_id': templateId,
      },
    });
    activeInspection = payload['inspection'] as Map<String, dynamic>;
    await _saveDraft(activeInspection!['id'] as int, activeInspection!);
    notifyListeners();
  }

  Future<void> updateResponse(
    int responseId, {
    required int score,
    required bool notApplicable,
    required bool passed,
    String? comment,
  }) async {
    final inspectionId = activeInspection!['id'] as int;
    await apiClient.patch('/inspection_responses/$responseId', {
      'response': {
        'score': score,
        'not_applicable': notApplicable,
        'passed': passed,
        'comment': comment
      },
    });
    await reloadInspection(inspectionId);
  }

  Future<void> uploadPhoto({
    required XFile file,
    required int? responseId,
    required String annotationJson,
    String? comment,
  }) async {
    final inspectionId = activeInspection!['id'] as int;
    await apiClient.uploadPhoto(
      file: file,
      responseId: responseId!,
      annotationJson: annotationJson,
      comment: comment,
    );
    await reloadInspection(inspectionId);
  }

  Future<void> updateComment(String comment) async {
    final inspectionId = activeInspection!['id'] as int;
    final payload = await apiClient.patch('/inspections/$inspectionId', {
      'inspection': {'general_comment': comment, 'comment': comment},
    });
    activeInspection = payload['inspection'] as Map<String, dynamic>;
    await _saveDraft(inspectionId, activeInspection!);
    notifyListeners();
  }

  Future<void> submit(String comment) async {
    final inspectionId = activeInspection!['id'] as int;
    final payload = await apiClient.post('/inspections/$inspectionId/submit', {
      'inspection': {'comment': comment},
    });
    activeInspection = payload['inspection'] as Map<String, dynamic>;
    await drafts.clearDraft(inspectionId);
    await loadHistory();
    notifyListeners();
  }

  Future<void> reloadInspection(int inspectionId) async {
    final payload = await apiClient.get('/inspections/$inspectionId');
    activeInspection = payload['inspection'] as Map<String, dynamic>;
    await _saveDraft(inspectionId, activeInspection!);
    notifyListeners();
  }

  Future<void> loadHistory() async {
    history =
        (await apiClient.get('/inspections'))['inspections'] as List<dynamic>;
    notifyListeners();
  }

  Future<void> loadDashboard() async {
    dashboard = (await apiClient.get('/dashboard'))['dashboard']
        as Map<String, dynamic>;
    notifyListeners();
  }

  Future<void> loadActions() async {
    actions = (await apiClient.get('/corrective_actions'))['corrective_actions']
        as List<dynamic>;
    notifyListeners();
  }

  Future<void> createAction(int responseId, String title) async {
    final inspectionId = activeInspection!['id'] as int;
    await apiClient.post('/corrective_actions', {
      'corrective_action': {
        'inspection_id': inspectionId,
        'inspection_response_id': responseId,
        'title': title,
        'description': title,
        'severity': 'High',
        'status': 'Open',
      },
    });
    await loadActions();
  }

  Future<void> _saveDraft(
      int inspectionId, Map<String, dynamic> payload) async {
    try {
      await drafts.saveDraft(inspectionId, payload);
    } catch (error) {
      debugPrint('Draft save failed: $error');
    }
  }
}

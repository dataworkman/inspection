import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../drafts/local_draft_storage.dart';

class InspectionState extends ChangeNotifier {
  InspectionState(this.apiClient, this.drafts);

  final ApiClient apiClient;
  final LocalDraftStorage drafts;

  List<dynamic> stores = [];
  List<dynamic> history = [];
  Map<String, dynamic>? dashboard;
  Map<String, dynamic>? activeInspection;

  Future<void> loadStores() async {
    stores = (await apiClient.get('/stores'))['stores'] as List<dynamic>;
    notifyListeners();
  }

  Future<void> startInspection(int storeId) async {
    final payload = await apiClient.post('/stores/$storeId/inspections', {});
    activeInspection = payload['inspection'] as Map<String, dynamic>;
    await drafts.saveDraft(activeInspection!['id'] as int, activeInspection!);
    notifyListeners();
  }

  Future<void> updateResponse(int responseId, {required int score, required bool passed, String? comment}) async {
    final inspectionId = activeInspection!['id'] as int;
    await apiClient.patch('/inspections/$inspectionId/responses/$responseId', {
      'response': {'score': score, 'passed': passed, 'comment': comment},
    });
    await reloadInspection(inspectionId);
  }

  Future<void> uploadPhoto({
    required File file,
    required int? responseId,
    required String annotationJson,
    String? comment,
  }) async {
    final inspectionId = activeInspection!['id'] as int;
    await apiClient.uploadPhoto(
      inspectionId: inspectionId,
      file: file,
      responseId: responseId,
      annotationJson: annotationJson,
      comment: comment,
    );
    await reloadInspection(inspectionId);
  }

  Future<void> updateComment(String comment) async {
    final inspectionId = activeInspection!['id'] as int;
    final payload = await apiClient.patch('/inspections/$inspectionId', {
      'inspection': {'comment': comment},
    });
    activeInspection = payload['inspection'] as Map<String, dynamic>;
    await drafts.saveDraft(inspectionId, activeInspection!);
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
    await drafts.saveDraft(inspectionId, activeInspection!);
    notifyListeners();
  }

  Future<void> loadHistory() async {
    history = (await apiClient.get('/inspections'))['inspections'] as List<dynamic>;
    notifyListeners();
  }

  Future<void> loadDashboard() async {
    dashboard = (await apiClient.get('/dashboard'))['dashboard'] as Map<String, dynamic>;
    notifyListeners();
  }
}

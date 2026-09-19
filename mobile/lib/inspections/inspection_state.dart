import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../drafts/local_draft_storage.dart';

class _ResponseSnapshot {
  const _ResponseSnapshot({
    required this.inspectionId,
    required this.score,
    required this.notApplicable,
    required this.passed,
    this.comment,
  });

  final int inspectionId;
  final int score;
  final bool notApplicable;
  final bool passed;
  final String? comment;
}

class InspectionState extends ChangeNotifier {
  InspectionState(this.apiClient, this.drafts);

  static const responseSaveDelay = Duration(milliseconds: 700);
  static const commentSaveDelay = Duration(milliseconds: 800);

  final ApiClient apiClient;
  final LocalDraftStorage drafts;

  // Edits are kept here (not in the widgets) so they survive leaving the
  // screen and can be flushed right before submitting. Latest edit wins per
  // response; saves for one response run in order.
  final Map<int, _ResponseSnapshot> _pendingResponses = {};
  final Map<int, Timer> _responseTimers = {};
  final Map<int, Future<void>> _responseTails = {};
  final Set<Future<void>> _inFlight = {};
  String? _pendingComment;
  int? _pendingCommentInspectionId;
  Timer? _commentTimer;
  Future<void>? _commentTail;

  /// Message of the last failed background save; cleared once saving works again.
  String? saveError;

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
    int? inspectionId,
  }) async {
    final targetInspectionId = inspectionId ?? activeInspection!['id'] as int;
    await apiClient.patch('/inspection_responses/$responseId', {
      'response': {
        'score': score,
        'not_applicable': notApplicable,
        'passed': passed,
        'comment': comment
      },
    });
    if (activeInspection?['id'] == targetInspectionId) {
      await reloadInspection(targetInspectionId);
    }
  }

  /// Queues a save of one checklist response. Toggles and sliders pass
  /// [immediate]; typing is debounced so it does not fire a request per key.
  void scheduleResponseSave(
    int responseId, {
    required int score,
    required bool notApplicable,
    required bool passed,
    String? comment,
    bool immediate = false,
  }) {
    _pendingResponses[responseId] = _ResponseSnapshot(
      inspectionId: activeInspection!['id'] as int,
      score: score,
      notApplicable: notApplicable,
      passed: passed,
      comment: comment,
    );
    _responseTimers.remove(responseId)?.cancel();
    if (immediate) {
      _saveResponse(responseId);
    } else {
      _responseTimers[responseId] = Timer(responseSaveDelay, () {
        _responseTimers.remove(responseId);
        _saveResponse(responseId);
      });
    }
  }

  /// Queues a save of the inspection-level comment (debounced).
  void scheduleCommentSave(String comment) {
    _pendingComment = comment;
    _pendingCommentInspectionId = activeInspection!['id'] as int;
    _commentTimer?.cancel();
    _commentTimer = Timer(commentSaveDelay, _saveComment);
  }

  /// Sends everything that is still waiting (including saves that failed
  /// earlier) and completes when the server has it. Throws if a save fails;
  /// the unsaved edits stay queued for a retry.
  Future<void> flushPendingSaves() async {
    for (final responseId in _pendingResponses.keys.toList()) {
      _responseTimers.remove(responseId)?.cancel();
      _saveResponse(responseId);
    }
    if (_pendingComment != null) _saveComment();
    await Future.wait(_inFlight.toList());
  }

  Future<void> _saveResponse(int responseId) {
    final tail = _responseTails[responseId];
    late final Future<void> next;
    next = (tail ?? Future<void>.value())
        .catchError((_) {})
        .then((_) => _runResponseSave(responseId));
    _responseTails[responseId] = next;
    return _track(next, onDone: () {
      if (identical(_responseTails[responseId], next)) {
        _responseTails.remove(responseId);
      }
    });
  }

  Future<void> _runResponseSave(int responseId) async {
    final snapshot = _pendingResponses.remove(responseId);
    if (snapshot == null) return;
    try {
      await updateResponse(
        responseId,
        inspectionId: snapshot.inspectionId,
        score: snapshot.score,
        notApplicable: snapshot.notApplicable,
        passed: snapshot.passed,
        comment: snapshot.comment,
      );
      _clearSaveError();
    } catch (error) {
      _pendingResponses.putIfAbsent(responseId, () => snapshot);
      _reportSaveError(error);
      rethrow;
    }
  }

  Future<void> _saveComment() {
    _commentTimer?.cancel();
    _commentTimer = null;
    late final Future<void> next;
    next = (_commentTail ?? Future<void>.value())
        .catchError((_) {})
        .then((_) => _runCommentSave());
    _commentTail = next;
    return _track(next, onDone: () {
      if (identical(_commentTail, next)) _commentTail = null;
    });
  }

  Future<void> _runCommentSave() async {
    final comment = _pendingComment;
    final inspectionId = _pendingCommentInspectionId;
    if (comment == null || inspectionId == null) return;
    _pendingComment = null;
    try {
      await updateComment(comment, inspectionId: inspectionId);
      _clearSaveError();
    } catch (error) {
      _pendingComment ??= comment;
      _pendingCommentInspectionId ??= inspectionId;
      _reportSaveError(error);
      rethrow;
    }
  }

  Future<void> _track(Future<void> future, {required VoidCallback onDone}) {
    _inFlight.add(future);
    void done() {
      _inFlight.remove(future);
      onDone();
    }

    future.then((_) => done(), onError: (_) => done());
    return future;
  }

  void _reportSaveError(Object error) {
    saveError = error.toString();
    notifyListeners();
  }

  void _clearSaveError() {
    if (saveError == null) return;
    if (_pendingResponses.isEmpty && _pendingComment == null) {
      saveError = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final timer in _responseTimers.values) {
      timer.cancel();
    }
    _commentTimer?.cancel();
    super.dispose();
  }

  Future<void> uploadPhoto({
    required XFile file,
    XFile? annotatedFile,
    required int? responseId,
    required String annotationJson,
    String? comment,
  }) async {
    final inspectionId = activeInspection!['id'] as int;
    await apiClient.uploadPhoto(
      file: file,
      annotatedFile: annotatedFile,
      responseId: responseId!,
      annotationJson: annotationJson,
      comment: comment,
    );
    await reloadInspection(inspectionId);
  }

  Future<void> updateComment(String comment, {int? inspectionId}) async {
    final targetInspectionId = inspectionId ?? activeInspection!['id'] as int;
    final payload = await apiClient.patch('/inspections/$targetInspectionId', {
      'inspection': {'general_comment': comment, 'comment': comment},
    });
    if (activeInspection?['id'] != targetInspectionId) return;
    activeInspection = payload['inspection'] as Map<String, dynamic>;
    await _saveDraft(targetInspectionId, activeInspection!);
    notifyListeners();
  }

  Future<void> submit(String comment) async {
    final inspectionId = activeInspection!['id'] as int;
    // The final comment travels with the submit request itself.
    _commentTimer?.cancel();
    _commentTimer = null;
    _pendingComment = null;
    try {
      await flushPendingSaves();
    } catch (error) {
      throw ApiException('Could not save your latest changes: $error', 0);
    }
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

  Future<Map<String, dynamic>> loadInspectionDetail(int inspectionId) async {
    final payload = await apiClient.get('/inspections/$inspectionId');
    return payload['inspection'] as Map<String, dynamic>;
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

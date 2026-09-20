import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../drafts/local_draft_storage.dart';

const correctiveActionSeverities = ['Low', 'Medium', 'High', 'Critical'];
const correctiveActionStatuses = [
  'Open',
  'In Progress',
  'Resolved',
  'Verified'
];

/// Statuses a role may set. Mirrors the server: store managers can only move
/// an action to In Progress or Resolved; closing it out is for admins and
/// inspectors.
List<String> correctiveActionStatusesFor(String? role) =>
    role == 'store_manager'
        ? const ['In Progress', 'Resolved']
        : correctiveActionStatuses;

/// Same rule as the server: an item passes at 70% of its points or more;
/// unanswered (0) and N/A items have no result.
const passRatio = 0.7;

bool? passedFor({
  required int score,
  required Object? maxScore,
  required bool notApplicable,
}) {
  final max = (maxScore as num?)?.toDouble();
  if (notApplicable || score <= 0 || max == null || max <= 0) return null;
  return score / max >= passRatio;
}

class _ResponseSnapshot {
  const _ResponseSnapshot({
    required this.inspectionId,
    required this.score,
    required this.notApplicable,
    this.comment,
  });

  factory _ResponseSnapshot.fromJson(
          int inspectionId, Map<String, dynamic> json) =>
      _ResponseSnapshot(
        inspectionId: inspectionId,
        score: (json['score'] as num?)?.toInt() ?? 0,
        notApplicable: json['not_applicable'] == true,
        comment: json['comment'] as String?,
      );

  final int inspectionId;
  final int score;
  final bool notApplicable;
  final String? comment;

  Map<String, dynamic> toJson() => {
        'score': score,
        'not_applicable': notApplicable,
        'comment': comment,
      };
}

/// Whether trying again later can help (no connection, server trouble).
bool _isRetryable(Object error) =>
    error is ApiException &&
    (error.isNetworkError ||
        error.statusCode >= 500 ||
        error.statusCode == 408 ||
        error.statusCode == 429);

/// The edit can never be applied (the inspection is gone, submitted or not the
/// user's), so keeping it queued would only block them.
bool _isPermanent(Object error) =>
    error is ApiException && const [403, 404, 409].contains(error.statusCode);

class InspectionState extends ChangeNotifier {
  InspectionState(this.apiClient, this.drafts);

  static const responseSaveDelay = Duration(milliseconds: 700);
  static const commentSaveDelay = Duration(milliseconds: 800);
  static const retryInterval = Duration(seconds: 20);

  /// The local database is only a safety net. If it stops answering it must
  /// never hold up talking to the server, so every local call gives up after this.
  static const localStoreTimeout = Duration(seconds: 5);

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

  Timer? _retryTimer;
  // Edits the server rejected as invalid (422): shown to the user, not retried
  // in the background until they change them.
  final Set<String> _stuck = {};

  /// Message of the last failed background save; cleared once saving works again.
  String? saveError;

  /// True when [saveError] is temporary and the edits will be sent again by
  /// themselves.
  bool saveErrorWillRetry = false;

  /// Why the last refresh of the lists failed (null when it worked).
  String? loadError;

  /// True once the lists have been refreshed at least once (so an empty list
  /// means "nothing there", not "still loading").
  bool listsLoaded = false;

  /// Unfinished inspections saved on this device (for resuming offline).
  List<Map<String, dynamic>> localDrafts = [];

  // Bumped by reset(); saves that started before it must not touch new state.
  int _epoch = 0;

  bool get hasPendingSaves =>
      _pendingResponses.isNotEmpty ||
      _pendingComment != null ||
      _inFlight.isNotEmpty;

  /// Forgets everything belonging to the signed-in user (after logging out or
  /// when the session ended). [clearLocalData] also wipes the saved drafts on
  /// the device; it is false when the session merely expired, so unsent work
  /// survives until the same user signs in again.
  void reset({bool clearLocalData = true}) {
    _epoch++;
    for (final timer in _responseTimers.values) {
      timer.cancel();
    }
    _responseTimers.clear();
    _commentTimer?.cancel();
    _commentTimer = null;
    _pendingResponses.clear();
    _pendingComment = null;
    _pendingCommentInspectionId = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stuck.clear();
    saveError = null;
    saveErrorWillRetry = false;
    loadError = null;
    localDrafts = [];
    listsLoaded = false;
    stores = [];
    templates = [];
    history = [];
    actions = [];
    dashboard = null;
    activeInspection = null;
    if (clearLocalData) {
      drafts.clearAll().catchError((Object error) {
        debugPrint('Clearing drafts failed: $error');
      });
    }
    notifyListeners();
  }

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

  static const openStatuses = ['draft', 'in_progress'];

  /// The user's own unfinished inspection of a store, if any.
  Map<String, dynamic>? openInspectionFor(int storeId, int? userId) {
    for (final item in history) {
      final inspection = item as Map<String, dynamic>;
      if (!openStatuses.contains(inspection['status'])) continue;
      if ((inspection['store'] as Map<String, dynamic>)['id'] != storeId) {
        continue;
      }
      final inspector = inspection['inspector'] as Map<String, dynamic>?;
      if (inspector != null && inspector['id'] == userId) return inspection;
    }
    return null;
  }

  /// The most recent finished inspection of a store (the history is newest
  /// first), if any.
  Map<String, dynamic>? latestSubmittedFor(int storeId) {
    for (final item in history) {
      final inspection = item as Map<String, dynamic>;
      if (inspection['status'] == 'submitted' &&
          (inspection['store'] as Map<String, dynamic>)['id'] == storeId) {
        return inspection;
      }
    }
    return null;
  }

  /// Loads an unfinished inspection and makes it the active one.
  ///
  /// Without a connection the copy saved on this device is used instead, so an
  /// inspection can be continued offline.
  Future<void> resumeInspection(int inspectionId) async {
    Map<String, dynamic> detail;
    try {
      detail = await loadInspectionDetail(inspectionId);
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      final saved = await _loadSavedDraft(inspectionId);
      if (saved == null) rethrow;
      detail = saved;
    }
    await _activate(detail);
  }

  Future<Map<String, dynamic>?> _loadSavedDraft(int inspectionId) async {
    try {
      return await drafts.loadDraft(inspectionId).timeout(localStoreTimeout);
    } catch (error) {
      debugPrint('Reading draft failed: $error');
      return null;
    }
  }

  /// Makes [payload] the active inspection, showing edits that have not
  /// reached the server yet on top of it, and keeps a copy on the device.
  Future<void> _activate(Map<String, dynamic> payload) async {
    activeInspection = _withPendingApplied(payload);
    notifyListeners();
    // Not awaited: the local copy must never delay the screen or a save.
    unawaited(_saveDraft(payload['id'] as int, activeInspection!));
  }

  Map<String, dynamic> _withPendingApplied(Map<String, dynamic> payload) {
    final result = {...payload};
    final responses = payload['responses'];
    if (responses is List) {
      result['responses'] = [
        for (final raw in responses)
          if (raw is Map<String, dynamic> &&
              _pendingResponses[raw['id']] != null)
            {
              ...raw,
              ..._pendingResponses[raw['id']]!.toJson(),
              // Derived like the server does, so the result agrees offline.
              'passed': passedFor(
                score: _pendingResponses[raw['id']]!.score,
                maxScore: raw['max_score'],
                notApplicable: _pendingResponses[raw['id']]!.notApplicable,
              ),
            }
          else
            raw,
      ];
    }
    if (_pendingComment != null &&
        _pendingCommentInspectionId == payload['id']) {
      result['comment'] = _pendingComment;
    }
    return result;
  }

  Future<void> startInspection(int storeId, int templateId) async {
    final payload = await apiClient.post('/inspections', {
      'inspection': {
        'store_id': storeId,
        'inspection_template_id': templateId,
      },
    });
    await _activate(payload['inspection'] as Map<String, dynamic>);
  }

  Future<void> updateResponse(
    int responseId, {
    required int score,
    required bool notApplicable,
    String? comment,
    int? inspectionId,
  }) async {
    final targetInspectionId = inspectionId ?? activeInspection!['id'] as int;
    await apiClient.patch('/inspection_responses/$responseId', {
      'response': {
        'score': score,
        'not_applicable': notApplicable,
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
    String? comment,
    bool immediate = false,
  }) {
    final snapshot = _ResponseSnapshot(
      inspectionId: activeInspection!['id'] as int,
      score: score,
      notApplicable: notApplicable,
      comment: comment,
    );
    _pendingResponses[responseId] = snapshot;
    _stuck.remove('response:$responseId');
    _persist('response', responseId, snapshot.inspectionId, snapshot.toJson());
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
    _stuck.remove('comment');
    _persist('comment', _pendingCommentInspectionId!,
        _pendingCommentInspectionId!, {'comment': comment});
    _commentTimer?.cancel();
    _commentTimer = Timer(commentSaveDelay, _saveComment);
  }

  /// Sends everything that is still waiting (including saves that failed
  /// earlier) and completes when the server has it. Throws if a save fails;
  /// the unsaved edits stay queued for a retry.
  Future<void> flushPendingSaves({bool includeStuck = true}) async {
    for (final responseId in _pendingResponses.keys.toList()) {
      if (!includeStuck && _stuck.contains('response:$responseId')) continue;
      _responseTimers.remove(responseId)?.cancel();
      _saveResponse(responseId);
    }
    if (_pendingComment != null &&
        (includeStuck || !_stuck.contains('comment'))) {
      _saveComment();
    }
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
    final epoch = _epoch;
    try {
      await updateResponse(
        responseId,
        inspectionId: snapshot.inspectionId,
        score: snapshot.score,
        notApplicable: snapshot.notApplicable,
        comment: snapshot.comment,
      );
      // Keep the stored copy if a newer edit was queued meanwhile.
      if (!_pendingResponses.containsKey(responseId)) {
        _unpersist('response', responseId);
      }
      _clearSaveError();
    } catch (error) {
      if (epoch == _epoch) {
        if (_isPermanent(error)) {
          _unpersist('response', responseId);
          _reportSaveError(error, note: 'Some changes could not be applied');
        } else {
          _pendingResponses.putIfAbsent(responseId, () => snapshot);
          _handleRetryableFailure('response:$responseId', error);
        }
      }
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
    final epoch = _epoch;
    try {
      await updateComment(comment, inspectionId: inspectionId);
      if (_pendingComment == null) _unpersist('comment', inspectionId);
      _clearSaveError();
    } catch (error) {
      if (epoch == _epoch) {
        if (_isPermanent(error)) {
          _unpersist('comment', inspectionId);
          _reportSaveError(error, note: 'Some changes could not be applied');
        } else {
          _pendingComment ??= comment;
          _pendingCommentInspectionId ??= inspectionId;
          _handleRetryableFailure('comment', error);
        }
      }
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

  void _reportSaveError(Object error, {String? note, bool willRetry = false}) {
    saveError = note == null ? error.toString() : '$note: $error';
    saveErrorWillRetry = willRetry;
    notifyListeners();
  }

  void _clearSaveError() {
    if (saveError == null) return;
    if (_pendingResponses.isEmpty && _pendingComment == null) {
      saveError = null;
      saveErrorWillRetry = false;
      notifyListeners();
    }
  }

  void _handleRetryableFailure(String key, Object error) {
    final retry = _isRetryable(error);
    if (retry) {
      _stuck.remove(key);
      _ensureRetryTimer();
    } else {
      _stuck.add(key);
    }
    _reportSaveError(error, willRetry: retry);
  }

  /// While edits are waiting because the connection failed, try again by
  /// itself so the inspector does not have to keep pressing Retry.
  void _ensureRetryTimer() {
    _retryTimer ??= Timer.periodic(retryInterval, (_) => _retryTick());
  }

  void _retryTick() {
    final waiting =
        _pendingResponses.keys.any((id) => !_stuck.contains('response:$id')) ||
            (_pendingComment != null && !_stuck.contains('comment'));
    if (!waiting) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (_inFlight.isNotEmpty) return;
    flushPendingSaves(includeStuck: false).catchError((Object _) {});
  }

  // --- keeping unsent edits on the device ---

  void _persist(
      String kind, int key, int inspectionId, Map<String, dynamic> payload) {
    drafts.savePending(kind, key, inspectionId, payload).catchError((Object e) {
      debugPrint('Saving pending edit failed: $e');
    });
  }

  void _unpersist(String kind, int key) {
    drafts.deletePending(kind, key).catchError((Object e) {
      debugPrint('Removing pending edit failed: $e');
    });
  }

  /// Called once the signed-in user is known. Local data left by a different
  /// user is discarded; the user's own unsent edits are loaded and sent.
  Future<void> attachToUser(int userId) async {
    try {
      final owner = await drafts.owner().timeout(localStoreTimeout);
      if (owner != null && owner != userId) {
        await drafts.clearAll().timeout(localStoreTimeout);
      }
      await drafts.setOwner(userId).timeout(localStoreTimeout);
      await restorePendingSaves();
      await loadLocalDrafts();
    } catch (error) {
      debugPrint('Restoring local data failed: $error');
    }
  }

  /// Loads the edits that were still unsent when the app was last closed.
  Future<void> restorePendingSaves() async {
    final epoch = _epoch;
    final saved = await drafts.loadPending().timeout(localStoreTimeout);
    if (epoch != _epoch) return;

    // Oldest first, so a later edit of the same response wins.
    for (final item in saved.where((item) => item.kind == 'response')) {
      _pendingResponses.putIfAbsent(item.key,
          () => _ResponseSnapshot.fromJson(item.inspectionId, item.payload));
    }
    // Only one inspection comment is queued at a time; keep the newest.
    final comments = saved.where((item) => item.kind == 'comment');
    if (_pendingComment == null && comments.isNotEmpty) {
      final newest = comments.last;
      _pendingComment = newest.payload['comment'] as String? ?? '';
      _pendingCommentInspectionId = newest.inspectionId;
    }

    if (_pendingResponses.isNotEmpty || _pendingComment != null) {
      notifyListeners();
      _ensureRetryTimer();
      flushPendingSaves(includeStuck: false).catchError((Object _) {});
    }
  }

  Future<void> loadLocalDrafts() async {
    try {
      final saved = await drafts.loadDrafts().timeout(localStoreTimeout);
      localDrafts = [
        for (final draft in saved)
          if (openStatuses.contains(draft['status'])) draft,
      ];
    } catch (error) {
      debugPrint('Reading drafts failed: $error');
      localDrafts = [];
    }
    notifyListeners();
  }

  /// Reloads every list, remembering (not throwing) why it failed so the app
  /// can say "no connection" instead of silently showing empty lists.
  Future<void> refreshAll({bool includeDashboard = false}) async {
    Object? failure;
    await Future.wait([
      for (final load in [
        loadStores,
        loadTemplates,
        loadHistory,
        loadActions,
        if (includeDashboard) loadDashboard,
      ])
        () async {
          try {
            await load();
          } catch (error) {
            failure ??= error;
          }
        }(),
    ]);
    final error = failure;
    loadError = error == null
        ? null
        : (error is ApiException ? error.message : error.toString());
    listsLoaded = true;
    await loadLocalDrafts();
  }

  @override
  void dispose() {
    for (final timer in _responseTimers.values) {
      timer.cancel();
    }
    _commentTimer?.cancel();
    _retryTimer?.cancel();
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
    await _activate(payload['inspection'] as Map<String, dynamic>);
  }

  Future<void> submit(String comment) async {
    final inspectionId = activeInspection!['id'] as int;
    // The final comment travels with the submit request itself.
    _commentTimer?.cancel();
    _commentTimer = null;
    _pendingComment = null;
    _unpersist('comment', inspectionId);
    try {
      await flushPendingSaves();
    } catch (error) {
      throw ApiException('Could not save your latest changes: $error', 0);
    }
    final payload = await apiClient.post('/inspections/$inspectionId/submit', {
      'inspection': {'comment': comment},
    });
    activeInspection = payload['inspection'] as Map<String, dynamic>;
    await _localBestEffort(() => drafts.clearDraft(inspectionId));
    await loadHistory();
    notifyListeners();
  }

  Future<void> reloadInspection(int inspectionId) async {
    final payload = await apiClient.get('/inspections/$inspectionId');
    await _activate(payload['inspection'] as Map<String, dynamic>);
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

  /// Actions already raised for one checklist response.
  List<Map<String, dynamic>> actionsForResponse(int responseId) => [
        for (final action in actions)
          if ((action as Map<String, dynamic>)['inspection_response_id'] ==
              responseId)
            action,
      ];

  Future<Map<String, dynamic>> createAction(
    int responseId, {
    required String title,
    required String severity,
    String? description,
    DateTime? dueDate,
  }) async {
    final inspectionId = activeInspection!['id'] as int;
    final payload = await apiClient.post('/corrective_actions', {
      'corrective_action': {
        'inspection_id': inspectionId,
        'inspection_response_id': responseId,
        'title': title,
        'description': description ?? title,
        'severity': severity,
        'status': 'Open',
        if (dueDate != null) 'due_date': _dateOnly(dueDate),
      },
    });
    final created = payload['corrective_action'] as Map<String, dynamic>;
    actions = [created, ...actions];
    notifyListeners();
    return created;
  }

  Future<void> updateActionStatus(int actionId, String status) async {
    final payload = await apiClient.patch('/corrective_actions/$actionId', {
      'corrective_action': {'status': status},
    });
    final updated = payload['corrective_action'] as Map<String, dynamic>;
    actions = [
      for (final action in actions)
        (action as Map<String, dynamic>)['id'] == actionId ? updated : action,
    ];
    notifyListeners();
  }

  static String _dateOnly(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _saveDraft(
      int inspectionId, Map<String, dynamic> payload) async {
    await _localBestEffort(() => drafts.saveDraft(inspectionId, payload));
  }

  /// Runs a local-store call that is nice to have: it gives up after
  /// [localStoreTimeout] and its failure is only logged.
  Future<void> _localBestEffort(Future<void> Function() operation) async {
    try {
      await operation().timeout(localStoreTimeout);
    } catch (error) {
      debugPrint('Local store call failed: $error');
    }
  }
}

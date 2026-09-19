import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/auth/auth_state.dart';
import 'package:store_inspection_mobile/inspections/inspection_state.dart';
import 'package:store_inspection_mobile/screens/home_screen.dart';
import 'package:store_inspection_mobile/screens/inspection_screen.dart';

import 'support/fakes.dart';

const _me = 5;

Map<String, dynamic> _summary({
  required int id,
  required String status,
  required int storeId,
  required int inspectorId,
  String storeName = 'Downtown',
}) =>
    {
      'id': id,
      'status': status,
      'score': 0,
      'grade': null,
      'store': {'id': storeId, 'name': storeName},
      'inspector': {'id': inspectorId},
    };

Map<String, dynamic> _detail({required int id, String comment = ''}) => {
      'id': id,
      'status': 'in_progress',
      'score': 60,
      'comment': comment,
      'store': {
        'id': 1,
        'name': 'Downtown',
        'store_code': 'DT',
        'address': 'Main'
      },
      'inspector': {'id': _me},
      'responses': [
        {
          'id': 1,
          'title': 'Floor cleanliness',
          'category': 'Cleanliness',
          'category_position': 1,
          'position': 1,
          'score': 3,
          'max_score': 5,
          'not_applicable': false,
          'photos': [],
        },
      ],
    };

void main() {
  late RecordingApiClient api;
  late InspectionState state;

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider(
              create: (_) =>
                  AuthState(api)..user = {'id': _me, 'role': 'inspector'}),
        ],
        child: MaterialApp(home: Scaffold(body: body)),
      ),
    );
  }

  void setUpState({List<Map<String, dynamic>> history = const []}) {
    api = RecordingApiClient()
      ..historyPayload = [...history]
      ..inspectionPayload = _detail(id: 12, comment: 'draft comment');
    state = InspectionState(api, NoDraftStorage())
      ..stores = [
        {'id': 1, 'name': 'Downtown', 'store_code': 'DT', 'address': 'Main'},
        {'id': 2, 'name': 'Airport', 'store_code': 'AP', 'address': 'Gate'},
      ]
      ..templates = [
        {'id': 3, 'name': 'Standard'},
      ]
      ..history = [...history];
  }

  group('store list', () {
    testWidgets('offers Resume only for the user\'s own unfinished inspection',
        (tester) async {
      setUpState(history: [
        _summary(id: 12, status: 'in_progress', storeId: 1, inspectorId: _me),
        // Someone else's unfinished inspection and a finished one do not count.
        _summary(
            id: 13,
            status: 'in_progress',
            storeId: 2,
            inspectorId: 99,
            storeName: 'Airport'),
        _summary(
            id: 14,
            status: 'submitted',
            storeId: 2,
            inspectorId: _me,
            storeName: 'Airport'),
      ]);
      await pump(tester, const StoreListView());

      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('Resume reopens the saved inspection instead of creating one',
        (tester) async {
      setUpState(history: [
        _summary(id: 12, status: 'in_progress', storeId: 1, inspectorId: _me),
      ]);
      await pump(tester, const StoreListView());

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(api.requests, contains('GET /inspections/12'));
      expect(api.requests, isNot(contains('POST /inspections')));
      expect(find.text('Floor cleanliness'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(
                  find.widgetWithText(TextField, 'draft comment'))
              .controller!
              .text,
          'draft comment');
      expect(state.activeInspection!['id'], 12);
    });

    testWidgets('a new inspection can still be started from the menu',
        (tester) async {
      setUpState(history: [
        _summary(id: 12, status: 'in_progress', storeId: 1, inspectorId: _me),
      ]);
      await pump(tester, const StoreListView());

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start a new inspection'));
      await tester.pumpAndSettle();

      expect(api.requests, contains('POST /inspections'));
      expect(
          api.bodies[api.requests.indexOf('POST /inspections')]['inspection'],
          {'store_id': 1, 'inspection_template_id': 3});
    });

    testWidgets('Start creates an inspection when nothing is open',
        (tester) async {
      setUpState();
      await pump(tester, const StoreListView());

      await tester.tap(find.text('Start').first);
      await tester.pumpAndSettle();

      expect(api.requests, contains('POST /inspections'));
      expect(find.text('Floor cleanliness'), findsOneWidget);
    });

    testWidgets('going back refreshes the list so Resume appears',
        (tester) async {
      setUpState();
      await pump(tester, const StoreListView());
      expect(find.text('Resume'), findsNothing);

      // The started inspection now exists on the server.
      api.historyPayload = [
        _summary(id: 12, status: 'in_progress', storeId: 1, inspectorId: _me),
      ];
      await tester.tap(find.text('Start').first);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('a failed resume is reported and nothing opens',
        (tester) async {
      setUpState(history: [
        _summary(id: 12, status: 'in_progress', storeId: 1, inspectorId: _me),
      ]);
      await pump(tester, const StoreListView());
      api.failGetsWith = ApiException('not found', 404);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(
          find.textContaining('Could not resume inspection'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });
  });

  group('history', () {
    testWidgets('an unfinished own inspection opens for editing',
        (tester) async {
      setUpState(history: [
        _summary(id: 12, status: 'in_progress', storeId: 1, inspectorId: _me),
      ]);
      await pump(tester, const HistoryView());

      await tester.tap(find.text('Downtown'));
      await tester.pumpAndSettle();

      expect(find.byType(ResponseTile), findsOneWidget);
      expect(state.activeInspection!['id'], 12);
    });

    testWidgets('a submitted inspection opens read-only', (tester) async {
      setUpState(history: [
        _summary(id: 12, status: 'submitted', storeId: 1, inspectorId: _me),
      ]);
      api.inspectionPayload = {..._detail(id: 12), 'status': 'submitted'};
      await pump(tester, const HistoryView());

      await tester.tap(find.text('Downtown'));
      await tester.pumpAndSettle();

      expect(find.text('Inspection Result'), findsOneWidget);
      expect(find.byType(ResponseTile), findsNothing);
    });

    testWidgets('someone else\'s unfinished inspection is not editable',
        (tester) async {
      setUpState(history: [
        _summary(id: 12, status: 'in_progress', storeId: 1, inspectorId: 99),
      ]);
      await pump(tester, const HistoryView());

      await tester.tap(find.text('Downtown'));
      await tester.pumpAndSettle();

      expect(find.text('Inspection Result'), findsOneWidget);
      expect(find.byType(ResponseTile), findsNothing);
    });
  });
}

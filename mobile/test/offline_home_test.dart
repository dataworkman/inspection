import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/auth/auth_state.dart';
import 'package:store_inspection_mobile/inspections/inspection_state.dart';
import 'package:store_inspection_mobile/screens/home_screen.dart';
import 'package:store_inspection_mobile/screens/inspection_screen.dart';

import 'support/fakes.dart';

Map<String, dynamic> savedInspection() => {
      'id': 7,
      'status': 'in_progress',
      'score': 60,
      'comment': 'note from before',
      'store': {
        'id': 1,
        'name': 'Downtown',
        'store_code': 'DT',
        'address': 'Main'
      },
      'inspector': {'id': 5},
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

  Future<void> pumpHome(WidgetTester tester, {bool offline = false}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'api_token': 'secret'});
    api = RecordingApiClient()..token = 'secret';
    if (offline) api.failGetsWith = ApiException('Cannot reach the server', 0);
    state = InspectionState(
        api, MemoryDraftStorage()..drafts[7] = savedInspection());
    final auth = AuthState(api)..user = {'id': 5, 'role': 'inspector'};
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: auth),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offline: says so and offers the inspection saved on the device',
      (tester) async {
    await pumpHome(tester, offline: true);

    expect(find.text('Cannot reach the server'), findsOneWidget);
    expect(find.text('SAVED ON THIS DEVICE'), findsOneWidget);
    expect(find.text('Downtown'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();

    // Opened from the local copy, with the saved comment and checklist.
    expect(find.byType(ResponseTile), findsOneWidget);
    expect(find.text('Floor cleanliness'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(
                find.widgetWithText(TextField, 'note from before'))
            .controller!
            .text,
        'note from before');
    expect(api.requests, isNot(contains('POST /inspections')));
  });

  testWidgets('online: the on-device list stays hidden and no banner shows',
      (tester) async {
    await pumpHome(tester);

    expect(find.text('SAVED ON THIS DEVICE'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('Retry reloads once the connection is back', (tester) async {
    await pumpHome(tester, offline: true);
    expect(find.text('Retry'), findsOneWidget);

    api.failGetsWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server'), findsNothing);
    expect(find.text('SAVED ON THIS DEVICE'), findsNothing);
    expect(state.loadError, isNull);
  });
}

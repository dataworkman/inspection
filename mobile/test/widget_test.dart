import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/drafts/local_draft_storage.dart';
import 'package:store_inspection_mobile/inspections/inspection_state.dart';
import 'package:store_inspection_mobile/screens/home_screen.dart';
import 'package:store_inspection_mobile/screens/inspection_screen.dart';
import 'package:store_inspection_mobile/screens/login_screen.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('shows login screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Store Inspection'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('dashboard renders current API payload', (tester) async {
    final state = InspectionState(
      ApiClient(baseUrl: 'http://example.test'),
      LocalDraftStorage(),
    )..dashboard = {
        'submitted_inspections': 3,
        'average_inspection_score': 82.5,
        'open_corrective_actions': 2,
        'critical_corrective_actions': 1,
        'attention_required': [
          {
            'store': {'name': 'Airport Bakery'},
            'latest_score': 65,
            'average_score': 72.25,
            'submitted_inspections': 2,
            'open_issues': 1,
          }
        ],
        'store_ranking': [
          {
            'store': {'name': 'Downtown Bakery'},
            'latest_score': 94,
            'average_score': 90.5,
            'submitted_inspections': 1,
            'open_issues': 0,
          }
        ],
      };

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: DashboardView())),
      ),
    );

    expect(find.text('Average score'), findsOneWidget);
    expect(find.text('82.5'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Open actions'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Airport Bakery'), findsOneWidget);
    expect(find.text('Downtown Bakery'), findsOneWidget);
  });

  testWidgets('inspection result groups rows by category', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: InspectionResultScreen(
        inspection: {
          'status': 'submitted',
          'score': 88,
          'grade': 'Good',
          'store': {
            'name': 'Downtown Bakery',
            'store_code': 'DT-BKY',
            'address': '101 Main Street',
          },
          'responses': [
            {
              'category': 'Service',
              'category_position': 2,
              'title': 'Greeting',
              'position': 1,
              'score': 4,
              'max_score': 5,
              'passed': true,
              'photos': [],
            },
            {
              'category': 'Cleanliness',
              'category_position': 1,
              'title': 'Counters',
              'position': 1,
              'score': 5,
              'max_score': 5,
              'passed': true,
              'photos': [],
            },
          ],
        },
      ),
    ));

    final cleanlinessTop = tester.getTopLeft(find.text('Cleanliness').first).dy;
    final serviceTop = tester.getTopLeft(find.text('Service').first).dy;

    expect(cleanlinessTop, lessThan(serviceTop));
    expect(find.text('Counters'), findsOneWidget);
    expect(find.text('Greeting'), findsOneWidget);
    expect(find.text('Item'), findsNWidgets(2));
  });

  testWidgets('response tile shows unanswered items as not scored',
      (tester) async {
    Map<String, dynamic> response(int score) => {
          'id': 1,
          'title': 'Floor cleanliness',
          'score': score,
          'max_score': 5,
          'not_applicable': false,
          'photos': [],
        };
    Future<void> pumpTile(Map<String, dynamic> data) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ResponseTile(
                  key: ValueKey(data['score']),
                  response: data,
                  onPhoto: (_, __) async {},
                  onPhotoSelected: (_, __, ___) async {},
                ),
              ),
            ),
          ),
        );

    await pumpTile(response(0));
    expect(find.text('-'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await pumpTile(response(4));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
  });

  group('response tile saving', () {
    late RecordingApiClient api;

    Future<void> pumpTile(WidgetTester tester) async {
      api = RecordingApiClient();
      final state = InspectionState(api, NoDraftStorage())
        ..activeInspection = {'id': 7, 'responses': []};
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ResponseTile(
                  response: const {
                    'id': 1,
                    'title': 'Floor cleanliness',
                    'score': 4,
                    'max_score': 5,
                    'not_applicable': false,
                    'passed': false,
                    'photos': [],
                  },
                  onPhoto: (_, __) async {},
                  onPhotoSelected: (_, __, ___) async {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('toggling Pass saves it', (tester) async {
      await pumpTile(tester);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      final saves = api.patchBodies('/inspection_responses/1');
      expect(saves, hasLength(1));
      expect(saves.single['response']['passed'], isTrue);
      expect(saves.single['response']['score'], 4);
    });

    testWidgets('typing a comment saves it after a pause', (tester) async {
      await pumpTile(tester);

      await tester.enterText(find.byType(TextField), 'Sticky floor');
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.patchBodies('/inspection_responses/1'), isEmpty);

      await tester.pump(InspectionState.responseSaveDelay);

      final saves = api.patchBodies('/inspection_responses/1');
      expect(saves, hasLength(1));
      expect(saves.single['response']['comment'], 'Sticky floor');
    });

    testWidgets('leaving the comment field saves it right away',
        (tester) async {
      await pumpTile(tester);

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Sticky floor');
      await tester.pump(const Duration(milliseconds: 100));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      final saves = api.patchBodies('/inspection_responses/1');
      expect(saves, hasLength(1));
      expect(saves.single['response']['comment'], 'Sticky floor');

      // The debounce timer must not send a duplicate afterwards.
      await tester.pump(InspectionState.responseSaveDelay);
      expect(api.patchBodies('/inspection_responses/1'), hasLength(1));
    });
  });

  group('attaching photos', () {
    late RecordingApiClient api;

    Future<void> pumpInspection(WidgetTester tester) async {
      api = RecordingApiClient();
      final inspection = {
        'id': 7,
        'status': 'in_progress',
        'score': 0,
        'store': {'name': 'Downtown', 'store_code': 'DT-1', 'address': 'Main'},
        'responses': [
          {
            'id': 1,
            'title': 'Floor cleanliness',
            'category': 'Cleanliness',
            'category_position': 1,
            'position': 1,
            'score': 4,
            'max_score': 5,
            'not_applicable': false,
            'photos': [],
          },
        ],
      };
      api.inspectionPayload = inspection;
      final state = InspectionState(api, NoDraftStorage())
        ..activeInspection = inspection;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            home: InspectionScreen(photoPicker: FakePhotoPicker()),
          ),
        ),
      );
    }

    Future<void> pickPhotoFromLibrary(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photo library'));
      await tester.pumpAndSettle();
      expect(find.text('Annotate photo'), findsOneWidget);
    }

    testWidgets('backing out of the annotation screen cancels the upload',
        (tester) async {
      await pumpInspection(tester);
      await pickPhotoFromLibrary(tester);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Annotate photo'), findsNothing);
      expect(api.uploads, isEmpty);
      expect(find.text('Uploading photo...'), findsNothing);
    });

    testWidgets('finishing without drawing uploads only the original',
        (tester) async {
      await pumpInspection(tester);
      await pickPhotoFromLibrary(tester);

      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();

      expect(api.uploads, hasLength(1));
      expect(api.uploads.single.responseId, 1);
      expect(api.uploads.single.annotated, isFalse);
      expect(api.uploads.single.annotationJson, '{"marks":[]}');
    });
  });
}

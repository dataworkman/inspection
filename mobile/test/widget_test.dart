import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/auth/auth_state.dart';
import 'package:store_inspection_mobile/drafts/local_draft_storage.dart';
import 'package:store_inspection_mobile/inspections/inspection_state.dart';
import 'package:store_inspection_mobile/screens/home_screen.dart';
import 'package:store_inspection_mobile/screens/inspection_screen.dart';
import 'package:store_inspection_mobile/screens/login_screen.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('shows login screen', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AuthState(RecordingApiClient()),
      child: const MaterialApp(home: LoginScreen()),
    ));

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
    final state = InspectionState(RecordingApiClient(), NoDraftStorage());
    Future<void> pumpTile(Map<String, dynamic> data) => tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: state,
            child: MaterialApp(
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

  group('corrective actions', () {
    late RecordingApiClient api;
    late InspectionState state;

    Future<void> pumpTile(WidgetTester tester) async {
      api = RecordingApiClient();
      state = InspectionState(api, NoDraftStorage())
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
                    'score': 2,
                    'max_score': 5,
                    'not_applicable': false,
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

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Add corrective action'));
      await tester.pumpAndSettle();
      expect(find.text('New corrective action'), findsOneWidget);
    }

    IconButton actionButton(WidgetTester tester) =>
        tester.widget<IconButton>(find.descendant(
            of: find.byType(Badge), matching: find.byType(IconButton)));

    testWidgets('creates an action with the chosen details', (tester) async {
      await pumpTile(tester);
      await openDialog(tester);

      expect(find.widgetWithText(TextFormField, 'Floor cleanliness'),
          findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Floor cleanliness'),
          'Re-mop the floor');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Critical').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      final body = api.bodies[api.requests.indexOf('POST /corrective_actions')]
          ['corrective_action'] as Map<String, dynamic>;
      expect(body['title'], 'Re-mop the floor');
      expect(body['severity'], 'Critical');
      expect(body['inspection_id'], 7);
      expect(body['inspection_response_id'], 1);
      expect(body.containsKey('due_date'), isFalse);
      expect(find.text('Corrective action created'), findsOneWidget);
      expect(state.actionsForResponse(1), hasLength(1));
      expect(find.descendant(of: find.byType(Badge), matching: find.text('1')),
          findsOneWidget);
    });

    testWidgets('requires a title', (tester) async {
      await pumpTile(tester);
      await openDialog(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Floor cleanliness'), '  ');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a title'), findsOneWidget);
      expect(api.requests, isNot(contains('POST /corrective_actions')));
    });

    testWidgets('cancelling creates nothing', (tester) async {
      await pumpTile(tester);
      await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(api.requests, isEmpty);
      expect(actionButton(tester).onPressed, isNotNull);
    });

    testWidgets(
        'the button is disabled while creating, so a double tap cannot duplicate',
        (tester) async {
      await pumpTile(tester);
      final gate = Completer<void>();
      api.holdNextPost = gate;
      await openDialog(tester);
      await tester.tap(find.text('Create'));
      await tester.pump();
      await tester.pump();

      expect(actionButton(tester).onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();

      expect(actionButton(tester).onPressed, isNotNull);
      expect(api.requests.where((r) => r == 'POST /corrective_actions'),
          hasLength(1));
    });

    testWidgets('shows the server error and creates nothing on failure',
        (tester) async {
      await pumpTile(tester);
      api.failPostsWith = ApiException('Severity is invalid', 422);
      await openDialog(tester);

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(
          find.text('Could not create corrective action: Severity is invalid'),
          findsOneWidget);
      expect(state.actionsForResponse(1), isEmpty);
      expect(actionButton(tester).onPressed, isNotNull);
    });
  });

  group('corrective action list', () {
    late RecordingApiClient api;

    Future<void> pumpActions(WidgetTester tester, String role) async {
      api = RecordingApiClient()
        ..actionsPayload = [
          {
            'id': 5,
            'title': 'Repair display case seal',
            'description': 'Seal is damaged.',
            'severity': 'High',
            'status': 'Open',
            'due_date': '2026-10-01',
            'store': {'name': 'Downtown'},
            'assigned_to': {'name': 'Manager'},
          },
        ];
      final state = InspectionState(api, NoDraftStorage());
      await state.loadActions();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider(
                create: (_) => AuthState(api)..user = {'role': role}),
          ],
          child: const MaterialApp(home: Scaffold(body: ActionsView())),
        ),
      );
    }

    Finder inSheet(String text) => find.descendant(
        of: find.byType(BottomSheet), matching: find.text(text));

    testWidgets('an inspector can set any status', (tester) async {
      await pumpActions(tester, 'inspector');

      await tester.tap(find.text('Repair display case seal'));
      await tester.pumpAndSettle();

      expect(inSheet('Seal is damaged.'), findsOneWidget);
      for (final status in ['Open', 'In Progress', 'Resolved', 'Verified']) {
        expect(inSheet(status), findsOneWidget, reason: status);
      }

      await tester.tap(inSheet('Resolved'));
      await tester.pumpAndSettle();

      expect(
          api.patchBodies('/corrective_actions/5').single['corrective_action'],
          {'status': 'Resolved'});
      expect(find.text('Resolved'), findsOneWidget);
    });

    testWidgets('a store manager can only choose In Progress or Resolved',
        (tester) async {
      await pumpActions(tester, 'store_manager');

      await tester.tap(find.text('Repair display case seal'));
      await tester.pumpAndSettle();

      expect(inSheet('In Progress'), findsOneWidget);
      expect(inSheet('Resolved'), findsOneWidget);
      expect(inSheet('Verified'), findsNothing);
      expect(inSheet('Open'), findsNothing);
    });

    testWidgets('a failed update is reported and the list is unchanged',
        (tester) async {
      await pumpActions(tester, 'admin');
      api.failPatchesWith = ApiException('not found', 404);

      await tester.tap(find.text('Repair display case seal'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(inSheet('Verified'));
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Verified'));
      await tester.pumpAndSettle();

      expect(
          find.text('Could not update the action: not found'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('an empty list says so', (tester) async {
      api = RecordingApiClient();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: InspectionState(api, NoDraftStorage()),
          child: const MaterialApp(home: Scaffold(body: ActionsView())),
        ),
      );

      expect(find.text('No corrective actions'), findsOneWidget);
    });
  });

  group('logging out', () {
    late RecordingApiClient api;
    late InspectionState state;
    late AuthState auth;

    Future<void> pumpHome(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'api_token': 'secret'});
      api = RecordingApiClient()..token = 'secret';
      state = InspectionState(api, NoDraftStorage())
        ..activeInspection = {'id': 7, 'responses': []};
      // Wired like in main(): signing out resets the inspection state.
      auth = AuthState(
        api,
        onSignedOut: ({required sessionExpired}) =>
            state.reset(clearLocalData: !sessionExpired),
      )..user = {'id': 5, 'role': 'inspector'};
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

    testWidgets('logs out straight away when nothing is unsent',
        (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();

      expect(find.text('Unsent changes'), findsNothing);
      expect(api.requests, contains('DELETE /auth/logout'));
      expect(auth.signedIn, isFalse);
    });

    testWidgets('sends waiting edits before logging out', (tester) async {
      await pumpHome(tester);
      state.scheduleCommentSave('last words');

      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();

      expect(api.patchBodies('/inspections/7'), hasLength(1));
      expect(api.requests.indexOf('PATCH /inspections/7'),
          lessThan(api.requests.indexOf('DELETE /auth/logout')));
      expect(auth.signedIn, isFalse);
    });

    testWidgets('warns when edits cannot be sent and lets the user stay',
        (tester) async {
      await pumpHome(tester);
      api.failPatchesWith = ApiException('Cannot reach the server', 0);
      state.scheduleCommentSave('unsent');

      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Unsent changes'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(auth.signedIn, isTrue);
      expect(api.requests, isNot(contains('DELETE /auth/logout')));
      // A failed save keeps a background retry timer; stop it before the end.
      state.reset(clearLocalData: false);
    });

    testWidgets('can log out anyway, discarding the unsent edits',
        (tester) async {
      await pumpHome(tester);
      api.failPatchesWith = ApiException('Cannot reach the server', 0);
      state.scheduleCommentSave('unsent');

      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out anyway'));
      await tester.pumpAndSettle();

      expect(auth.signedIn, isFalse);
    });
  });

  testWidgets('the login screen explains an expired session', (tester) async {
    final auth = AuthState(RecordingApiClient())
      ..notice = 'Your session expired. Please sign in again.';
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: auth, child: const MaterialApp(home: LoginScreen())));

    expect(find.text('Your session expired. Please sign in again.'),
        findsOneWidget);
  });
}

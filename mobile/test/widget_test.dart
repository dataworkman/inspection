import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/drafts/local_draft_storage.dart';
import 'package:store_inspection_mobile/inspections/inspection_state.dart';
import 'package:store_inspection_mobile/screens/home_screen.dart';
import 'package:store_inspection_mobile/screens/login_screen.dart';

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
}

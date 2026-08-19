import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:store_inspection_mobile/screens/login_screen.dart';

void main() {
  testWidgets('shows login screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Store Inspection'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}

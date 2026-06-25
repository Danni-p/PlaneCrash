// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:planecrash/main.dart';

void main() {
  testWidgets('App boots smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PlaneCrashApp());
    await tester.pumpAndSettle();

    // We don't assert specific UI text here because the home screen is localized
    // and may change as the game evolves. This just ensures the widget tree builds.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

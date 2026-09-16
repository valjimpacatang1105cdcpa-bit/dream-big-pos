// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:dream_big_pos/main.dart';

void main() {
  testWidgets('shows the cashier access screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DreamBigPosApp());

    expect(find.text('DREAM BIG POS'), findsOneWidget);
    expect(find.text('Cashier Access'), findsOneWidget);
    expect(find.text('Select cashier'), findsOneWidget);
  });
}

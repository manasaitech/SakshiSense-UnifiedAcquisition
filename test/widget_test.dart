import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:unified_acquisition_app/main.dart';

void main() {
  testWidgets('collector shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Unified Research Acquisition'), findsOneWidget);
    expect(find.text('Acquisition Setup'), findsOneWidget);
    expect(find.text('BrainBit EEG'), findsOneWidget);
    expect(find.text('SakshiSense Ring'), findsOneWidget);
    expect(find.text('Laptop / microphone audio'), findsOneWidget);
    expect(find.text('Continue with connected devices'), findsOneWidget);
    expect(find.text('Open Demo Session'), findsOneWidget);
  });

  testWidgets('device screen renders on compact desktop widths',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.tap(find.byTooltip('Demo mode'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Demo BrainBit'), findsOneWidget);
    await tester.tap(find.byTooltip('Open session controls'));
    await tester.pumpAndSettle();
    expect(find.text('Session Control'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
  });
}

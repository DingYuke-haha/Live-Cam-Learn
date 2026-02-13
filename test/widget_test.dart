import 'package:flutter_test/flutter_test.dart';

import 'package:live_cam_learn/main.dart';

void main() {
  testWidgets('VLM Test Page loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the VLM Test page is displayed
    expect(find.text('VLM Test'), findsOneWidget);
    expect(find.text('Model Configuration'), findsOneWidget);
    expect(find.text('Image Processing'), findsOneWidget);
    expect(find.text('Response'), findsOneWidget);
  });
}

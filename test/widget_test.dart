import 'package:flutter_test/flutter_test.dart';

import 'package:yt_downloader/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const YTDownloaderApp());

    // Verify that the app title is shown
    expect(find.text('YT Music Downloader'), findsOneWidget);
  });
}

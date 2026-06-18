import 'package:flutter_test/flutter_test.dart';

import 'package:yt_downloader/main.dart';
import 'package:yt_downloader/services/library_service.dart';
import 'package:yt_downloader/services/player_service.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    final libraryService = LibraryService();
    final playerService = PlayerService();

    await tester.pumpWidget(
      YTDownloaderApp(
        libraryService: libraryService,
        playerService: playerService,
      ),
    );

    expect(find.text('播放器'), findsOneWidget);
  });
}

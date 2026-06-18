import 'package:flutter/material.dart';
import 'services/library_service.dart';
import 'services/player_service.dart';
import 'theme/app_theme.dart';
import 'pages/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final libraryService = LibraryService();
  await libraryService.load();
  final playerService = PlayerService();
  await playerService.initialize();

  runApp(
    YTDownloaderApp(
      libraryService: libraryService,
      playerService: playerService,
    ),
  );
}

class YTDownloaderApp extends StatelessWidget {
  final LibraryService libraryService;
  final PlayerService playerService;

  const YTDownloaderApp({
    super.key,
    required this.libraryService,
    required this.playerService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YT Music Downloader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: HomeShell(
        libraryService: libraryService,
        playerService: playerService,
      ),
    );
  }
}

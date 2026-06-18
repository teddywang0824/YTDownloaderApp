import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/incoming_share_service.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'player_page.dart';

class HomeShell extends StatefulWidget {
  final LibraryService libraryService;
  final PlayerService playerService;

  const HomeShell({
    super.key,
    required this.libraryService,
    required this.playerService,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;
  final ValueNotifier<String?> _sharedUrlNotifier = ValueNotifier<String?>(null);
  final IncomingShareService _incomingShareService = IncomingShareService();
  StreamSubscription<String>? _shareSub;

  @override
  void initState() {
    super.initState();
    _shareSub = _incomingShareService.sharedTextStream().listen(_handleSharedText);
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _sharedUrlNotifier.dispose();
    unawaited(widget.playerService.disposeService());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      PlayerPage(
        libraryService: widget.libraryService,
        playerService: widget.playerService,
        onNavigateToTab: _selectTab,
      ),
      LibraryPage(
        libraryService: widget.libraryService,
        playerService: widget.playerService,
      ),
      HomePage(
        onTrackDownloaded: _handleTrackDownloaded,
        incomingSharedUrl: _sharedUrlNotifier,
        onIncomingSharedUrlConsumed: _clearSharedUrl,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.bgSecondary,
        indicatorColor: AppColors.accentPurple.withValues(alpha: 0.18),
        selectedIndex: _currentIndex,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline_rounded),
            selectedIcon: Icon(Icons.play_circle_filled_rounded),
            label: '播放器',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: '音樂庫',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_rounded),
            label: '下載',
          ),
        ],
        onDestinationSelected: _selectTab,
      ),
    );
  }

  void _selectTab(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _handleTrackDownloaded(Track track) async {
    await widget.libraryService.addOrUpdateTrack(track);
    if (!mounted) return;
    setState(() => _currentIndex = 1);
  }

  void _handleSharedText(String text) {
    if (!mounted) return;
    setState(() => _currentIndex = 2);
    _sharedUrlNotifier.value = text;
  }

  void _clearSharedUrl() {
    _sharedUrlNotifier.value = null;
  }
}

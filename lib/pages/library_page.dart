import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';

class LibraryPage extends StatelessWidget {
  final LibraryService libraryService;
  final PlayerService playerService;

  const LibraryPage({
    super.key,
    required this.libraryService,
    required this.playerService,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([libraryService, playerService]),
      builder: (context, _) {
        final tracks = libraryService.tracks;

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final imported = await libraryService.importLocalTrack();
              if (imported != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已匯入 ${imported.title}')),
                );
              }
            },
            backgroundColor: AppColors.accentPurple,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('匯入音樂', style: TextStyle(color: Colors.white)),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '音樂庫',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '你可以播放下載回來的歌曲，也可以匯入本機 MP3 / M4A / AAC。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: tracks.isEmpty
                        ? _buildEmptyState(context)
                        : ListView.separated(
                            itemCount: tracks.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final track = tracks[index];
                              return _TrackTile(
                                track: track,
                                gainDb: libraryService.gainForTrack(track.id),
                                isActive:
                                    playerService.currentTrack?.id == track.id,
                                onPlay: () => playerService.playTrack(
                                  track,
                                  gainDb: libraryService.gainForTrack(track.id),
                                  queue: tracks,
                                  gainForTrack: libraryService.gainForTrack,
                                ),
                                onDelete: () => libraryService.removeTrack(track.id),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.library_music_rounded,
            color: AppColors.accentCyan,
            size: 42,
          ),
          const SizedBox(height: 14),
          Text(
            '音樂庫還沒有歌曲',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '先匯入本機音樂，或到下載頁把 YouTube 音樂抓進來，這裡就會自動記住歌曲和音量設定。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final Track track;
  final double gainDb;
  final bool isActive;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  const _TrackTile({
    required this.track,
    required this.gainDb,
    required this.isActive,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? AppColors.bgTertiary : AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? AppColors.accentPurple.withValues(alpha: 0.6)
              : AppColors.borderLight.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: AppColors.primaryGradient,
            ),
            child: const Icon(Icons.music_note_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${track.artist} • 記錄音量 ${gainDb >= 0 ? '+' : ''}${gainDb.toStringAsFixed(1)} dB',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onPlay,
            icon: const Icon(
              Icons.play_arrow_rounded,
              color: AppColors.accentCyan,
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

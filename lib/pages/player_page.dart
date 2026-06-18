import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';

class PlayerPage extends StatelessWidget {
  final LibraryService libraryService;
  final PlayerService playerService;
  final ValueChanged<int>? onNavigateToTab;

  const PlayerPage({
    super.key,
    required this.libraryService,
    required this.playerService,
    this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([libraryService, playerService]),
      builder: (context, _) {
        final track = playerService.currentTrack;
        final gainDb = track == null
            ? 0.0
            : libraryService.gainForTrack(track.id).clamp(-12.0, 16.0);
        final duration = playerService.duration;
        final position = playerService.position > duration && duration > Duration.zero
            ? duration
            : playerService.position;
        final tracks = libraryService.tracks;
        final hasPrevious = playerService.hasPrevious(tracks);
        final hasNext = playerService.hasNext(tracks);
        final sliderMax =
            duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();

        return Scaffold(
          backgroundColor: AppColors.bgPrimary,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '播放器',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '以播放體驗為主，下載回來的歌曲會自動保存到音樂庫。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                  const SizedBox(height: 24),
                  _buildNowPlayingCard(context, track, gainDb),
                  const SizedBox(height: 18),
                  _buildPlaybackCard(
                    context,
                    tracks: tracks,
                    hasPrevious: hasPrevious,
                    hasNext: hasNext,
                    position: position,
                    sliderMax: sliderMax,
                    duration: duration,
                  ),
                  const SizedBox(height: 18),
                  _buildRecentTracks(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNowPlayingCard(BuildContext context, Track? track, double gainDb) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: track == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.queue_music_rounded,
                  color: AppColors.accentCyan,
                  size: 28,
                ),
                const SizedBox(height: 12),
                Text(
                  '還沒有正在播放的歌曲',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '先從音樂庫挑一首歌，或切到下載頁把 YouTube 音樂存進來。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                        height: 1.5,
                      ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _QuickActionButton(
                      text: '前往音樂庫',
                      icon: Icons.library_music_rounded,
                      onPressed: () => onNavigateToTab?.call(1),
                    ),
                    _QuickActionButton(
                      text: '前往下載',
                      icon: Icons.download_rounded,
                      onPressed: () => onNavigateToTab?.call(2),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Now Playing',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.accentCyan,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 14),
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 26,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  track.artist,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 18),
                Text(
                  '目前記錄音量',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${gainDb >= 0 ? '+' : ''}${gainDb.toStringAsFixed(1)} dB',
                  style: const TextStyle(
                    color: AppColors.accentCyan,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPlaybackCard(
    BuildContext context, {
    required List<Track> tracks,
    required bool hasPrevious,
    required bool hasNext,
    required Duration position,
    required double sliderMax,
    required Duration duration,
  }) {
    final track = playerService.currentTrack;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '播放控制',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Spacer(),
              if (playerService.errorMessage != null)
                Flexible(
                  child: Text(
                    playerService.errorMessage!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accentPurple,
              inactiveTrackColor: AppColors.bgPrimary,
              thumbColor: AppColors.accentCyan,
              overlayColor: AppColors.accentCyan.withValues(alpha: 0.14),
              trackHeight: 6,
            ),
            child: Slider(
              value: position.inMilliseconds.toDouble().clamp(0.0, sliderMax),
              min: 0,
              max: sliderMax,
              onChanged: track == null
                  ? null
                  : (value) {
                      playerService.seek(Duration(milliseconds: value.round()));
                    },
            ),
          ),
          Row(
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: !hasPrevious || playerService.isPreparing
                    ? null
                    : () => playerService.playPrevious(
                          tracks,
                          gainForTrack: libraryService.gainForTrack,
                        ),
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: track == null
                    ? null
                    : () => playerService.seekBy(const Duration(seconds: -10)),
                icon: const Icon(Icons.replay_10_rounded),
              ),
              const SizedBox(width: 8),
              _PrimaryPlaybackButton(
                isPlaying: playerService.isPlaying,
                isDisabled: track == null || playerService.isPreparing,
                onPressed: playerService.togglePlayback,
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: track == null
                    ? null
                    : () => playerService.seekBy(const Duration(seconds: 10)),
                icon: const Icon(Icons.forward_10_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: !hasNext || playerService.isPreparing
                    ? null
                    : () => playerService.playNext(
                          tracks,
                          gainForTrack: libraryService.gainForTrack,
                        ),
                icon: const Icon(Icons.skip_next_rounded),
              ),
              // const Spacer(),
              // Text(
              //   playerService.isPreparing ? '正在準備...' : '可隨時調整音量',
              //   style: const TextStyle(
              //     color: AppColors.textMuted,
              //     fontSize: 12,
              //   ),
              // ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '歌曲音量',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accentCyan,
              inactiveTrackColor: AppColors.bgPrimary,
              thumbColor: AppColors.accentPurple,
            ),
            child: Slider(
              value: track == null
                  ? 0.0
                  : libraryService.gainForTrack(track.id).clamp(-12.0, 16.0),
              min: -12,
              max: 16,
              divisions: 56,
              onChanged: track == null
                  ? null
                  : (value) async {
                      await libraryService.setTrackGain(track.id, value);
                      await playerService.setTrackGainDb(value);
                    },
            ),
          ),
          if (track != null)
            Text(
              '調整結果會記錄在 app 內，下次播放同一首歌會自動套用。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                    height: 1.5,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentTracks(BuildContext context) {
    final allTracks = libraryService.tracks;
    final tracks = allTracks.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '最近加入',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => onNavigateToTab?.call(1),
                child: const Text('查看全部'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (tracks.isEmpty)
            Text(
              '音樂庫目前還是空的，可以先匯入本機歌曲，或到下載頁抓一首 YouTube 音樂。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                    height: 1.5,
                  ),
            )
          else
            ...tracks.map(
              (track) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppColors.bgTertiary,
                  child: Icon(
                    Icons.music_note_rounded,
                    color: AppColors.accentCyan,
                  ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.artist} • ${_formatDuration(track.duration ?? Duration.zero)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  onPressed: () => playerService.playTrack(
                    track,
                    gainDb: libraryService.gainForTrack(track.id),
                    queue: allTracks,
                    gainForTrack: libraryService.gainForTrack,
                  ),
                  icon: const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.accentPurple,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '00:00';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _QuickActionButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onPressed;

  const _QuickActionButton({
    required this.text,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(text),
    );
  }
}

class _PrimaryPlaybackButton extends StatelessWidget {
  final bool isPlaying;
  final bool isDisabled;
  final Future<void> Function() onPressed;

  const _PrimaryPlaybackButton({
    required this.isPlaying,
    required this.isDisabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isDisabled ? AppColors.bgTertiary : AppColors.accentPurple,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: isDisabled ? null : () => onPressed(),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: isDisabled ? AppColors.textMuted : Colors.white,
                size: 30,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isPlaying ? '暫停' : '播放',
          style: TextStyle(
            color: isDisabled ? AppColors.textMuted : AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

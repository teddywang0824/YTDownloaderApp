import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/video_info.dart';

/// A card that displays video metadata with a premium glass effect.
/// Responsive: stacks vertically on mobile, horizontal on desktop.
class VideoInfoCard extends StatelessWidget {
  final VideoInfo videoInfo;
  final VoidCallback? onTitleEdit;

  const VideoInfoCard({
    super.key,
    required this.videoInfo,
    this.onTitleEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 500;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: AppColors.cardGradient,
        border: Border.all(
          color: AppColors.borderLight.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentPurple.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isWide ? _buildHorizontalLayout(context) : _buildVerticalLayout(context),
      ),
    );
  }

  Widget _buildHorizontalLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildThumbnail(160, 100),
        const SizedBox(width: 20),
        Expanded(child: _buildInfo(context)),
      ],
    );
  }

  Widget _buildVerticalLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildThumbnail(double.infinity, 160),
        const SizedBox(height: 14),
        _buildInfo(context),
      ],
    );
  }

  Widget _buildThumbnail(double width, double height) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: width == double.infinity ? null : width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.bgTertiary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: videoInfo.thumbnailUrl != null
            ? Image.network(
                videoInfo.thumbnailUrl!,
                fit: BoxFit.cover,
                width: width == double.infinity ? null : width,
                height: height,
                errorBuilder: (context, error, stackTrace) {
                  return _buildThumbnailPlaceholder(width, height);
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _buildThumbnailLoading(width, height);
                },
              )
            : _buildThumbnailPlaceholder(width, height),
      ),
    );
  }

  Widget _buildThumbnailPlaceholder(double width, double height) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accentPurple.withValues(alpha: 0.2),
            AppColors.accentCyan.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        color: AppColors.accentPurple,
        size: 40,
      ),
    );
  }

  Widget _buildThumbnailLoading(double width, double height) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      color: AppColors.bgTertiary,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentPurple),
          ),
        ),
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          videoInfo.title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.3,
                fontSize: 16,
              ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        // Author
        Row(
          children: [
            const Icon(
              Icons.person_rounded,
              color: AppColors.accentCyan,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                videoInfo.author,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.accentCyan,
                      fontWeight: FontWeight.w500,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Duration
        Row(
          children: [
            const Icon(
              Icons.timer_rounded,
              color: AppColors.textMuted,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              videoInfo.durationFormatted,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

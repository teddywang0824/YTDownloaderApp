import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/video_info.dart';

/// Animated download progress bar with gradient fill and status text.
class DownloadProgressBar extends StatelessWidget {
  final DownloadProgress downloadProgress;

  const DownloadProgressBar({
    super.key,
    required this.downloadProgress,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: AppColors.cardGradient,
          border: Border.all(
            color: AppColors.borderLight.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentPurple.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildStatusIcon(),
                    const SizedBox(width: 10),
                    Text(
                      _getStatusTitle(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                // Percentage
                if (downloadProgress.state == DownloadState.downloading)
                  Text(
                    '${(downloadProgress.progress * 100).toInt()}%',
                    style: const TextStyle(
                      color: AppColors.accentCyan,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Progress bar
            _buildProgressBar(),
            if (downloadProgress.statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                downloadProgress.statusMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (downloadProgress.state) {
      case DownloadState.downloading:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentCyan),
          ),
        );
      case DownloadState.completed:
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.primaryGradient,
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
        );
      case DownloadState.error:
        return const Icon(Icons.error_rounded, color: AppColors.error, size: 24);
      case DownloadState.fetchingInfo:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentPurple),
          ),
        );
      default:
        return const Icon(Icons.download_rounded,
            color: AppColors.textMuted, size: 24);
    }
  }

  String _getStatusTitle() {
    switch (downloadProgress.state) {
      case DownloadState.fetchingInfo:
        return '正在取得影片資訊...';
      case DownloadState.downloading:
        return '正在下載...';
      case DownloadState.completed:
        return '下載完成！';
      case DownloadState.error:
        return '下載失敗';
      default:
        return '準備下載';
    }
  }

  Widget _buildProgressBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            // Background
            Container(
              decoration: BoxDecoration(
                color: AppColors.bgTertiary,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            // Progress fill
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              widthFactor: downloadProgress.progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: _getProgressGradient(),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentCyan.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LinearGradient _getProgressGradient() {
    switch (downloadProgress.state) {
      case DownloadState.completed:
        return const LinearGradient(
          colors: [AppColors.success, Color(0xFF34D399)],
        );
      case DownloadState.error:
        return const LinearGradient(
          colors: [AppColors.error, Color(0xFFF87171)],
        );
      default:
        return AppColors.primaryGradient;
    }
  }
}

/// An animated fractionally sized box.
class AnimatedFractionallySizedBox extends ImplicitlyAnimatedWidget {
  final double widthFactor;
  final Widget child;

  const AnimatedFractionallySizedBox({
    super.key,
    required super.duration,
    super.curve,
    required this.widthFactor,
    required this.child,
  });

  @override
  AnimatedFractionallySizedBoxState createState() =>
      AnimatedFractionallySizedBoxState();
}

class AnimatedFractionallySizedBoxState
    extends AnimatedWidgetBaseState<AnimatedFractionallySizedBox> {
  Tween<double>? _widthFactor;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _widthFactor = visitor(
      _widthFactor,
      widget.widthFactor,
      (dynamic value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: _widthFactor?.evaluate(animation) ?? widget.widthFactor,
      child: widget.child,
    );
  }
}

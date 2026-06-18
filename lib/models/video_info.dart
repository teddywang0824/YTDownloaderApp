/// Video information model for displaying metadata.
class VideoInfo {
  final String title;
  final String author;
  final Duration? duration;
  final String? thumbnailUrl;
  final String videoId;
  final String url;

  const VideoInfo({
    required this.title,
    required this.author,
    this.duration,
    this.thumbnailUrl,
    required this.videoId,
    required this.url,
  });

  String get durationFormatted {
    if (duration == null) return '--:--';
    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds % 60;
    if (duration!.inHours > 0) {
      final hours = duration!.inHours;
      return '${hours.toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Download state enum
enum DownloadState {
  idle,
  fetchingInfo,
  analyzingAudio,
  readyToDownload,
  downloading,
  completed,
  error,
}

/// Download progress model
class DownloadProgress {
  final double progress; // 0.0 to 1.0
  final String? statusMessage;
  final String? filePath;
  final String? errorMessage;
  final DownloadState state;

  const DownloadProgress({
    this.progress = 0.0,
    this.statusMessage,
    this.filePath,
    this.errorMessage,
    this.state = DownloadState.idle,
  });

  DownloadProgress copyWith({
    double? progress,
    String? statusMessage,
    String? filePath,
    String? errorMessage,
    DownloadState? state,
  }) {
    return DownloadProgress(
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage ?? this.errorMessage,
      state: state ?? this.state,
    );
  }
}

/// Download history item
class DownloadHistoryItem {
  final String title;
  final String author;
  final String filePath;
  final DateTime downloadedAt;
  final String? thumbnailUrl;

  const DownloadHistoryItem({
    required this.title,
    required this.author,
    required this.filePath,
    required this.downloadedAt,
    this.thumbnailUrl,
  });
}

/// Output volume strategy selected by the user.
enum VolumeAdjustmentMode {
  original,
  normalize,
  manual,
}

/// Loudness analysis returned from FFmpeg.
class AudioLoudnessAnalysis {
  static const double targetLufs = -14.0;
  static const double safeTruePeakDbtp = -1.5;

  final double integratedLufs;
  final double truePeakDbtp;
  final double loudnessRange;
  final double threshold;

  const AudioLoudnessAnalysis({
    required this.integratedLufs,
    required this.truePeakDbtp,
    required this.loudnessRange,
    required this.threshold,
  });

  double get normalizationGainEstimateDb => targetLufs - integratedLufs;

  double get safeManualGainDb {
    final peakLimitedGain = safeTruePeakDbtp - truePeakDbtp;
    final suggested = normalizationGainEstimateDb;
    if (suggested > peakLimitedGain) {
      return peakLimitedGain.clamp(-12.0, 12.0);
    }
    return suggested.clamp(-12.0, 12.0);
  }

  bool get manualBoostLimitedByPeak =>
      normalizationGainEstimateDb > (safeTruePeakDbtp - truePeakDbtp);

  String get summary {
    if (integratedLufs <= -18) return '這首歌偏小聲，建議先做標準化。';
    if (integratedLufs >= -11) return '這首歌本身偏大聲，保留原始音量或略降會比較安全。';
    return '這首歌的整體音量已接近常見串流平台水準。';
  }
}

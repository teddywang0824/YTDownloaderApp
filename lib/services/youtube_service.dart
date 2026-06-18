import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import '../models/video_info.dart';

class YouTubeService {
  YoutubeExplode? _yt;
  _PreparedAudioSource? _preparedAudioSource;
  _GeneratedPreview? _generatedPreview;

  YoutubeExplode get yt {
    _yt ??= YoutubeExplode();
    return _yt!;
  }

  void _resetClient() {
    _yt?.close();
    _yt = YoutubeExplode();
  }

  String? extractVideoId(String url) {
    try {
      return VideoId.parseVideoId(url);
    } catch (e) {
      return null;
    }
  }

  Future<VideoInfo> fetchVideoInfo(String url) async {
    final video = await yt.videos.get(url);
    final thumbnailUrl = video.thumbnails.highResUrl;

    return VideoInfo(
      title: video.title,
      author: video.author,
      duration: video.duration,
      thumbnailUrl: thumbnailUrl,
      videoId: video.id.value,
      url: url,
    );
  }

  Future<AudioLoudnessAnalysis> analyzeAudio({
    required String url,
    Function(double progress)? onProgress,
    Function(String status)? onStatus,
  }) async {
    onStatus?.call('正在準備音訊分析...');

    final prepared = await _prepareAudioSource(
      url: url,
      onProgress: onProgress,
      onStatus: onStatus,
      progressStart: 0.0,
      progressEnd: 0.7,
    );

    onStatus?.call('正在分析音量...');
    onProgress?.call(0.78);

    final command =
        '-i "${prepared.filePath}" -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null -';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final output = await session.getOutput();

    if (!ReturnCode.isSuccess(returnCode)) {
      throw Exception('音量分析失敗');
    }

    final analysis = _parseLoudnessAnalysis(output ?? '');
    if (analysis == null) {
      throw Exception('無法解析音量分析結果');
    }

    onProgress?.call(1.0);
    onStatus?.call('音量分析完成');
    return analysis;
  }

  /// Downloads audio and converts to MP3.
  Future<String> downloadAudio({
    required String url,
    required String fileName,
    String? customSavePath,
    VolumeAdjustmentMode volumeMode = VolumeAdjustmentMode.original,
    double manualGainDb = 0.0,
    Function(double progress)? onProgress,
    Function(String status)? onStatus,
  }) async {
    _resetClient();
    final prepared = await _prepareAudioSource(
      url: url,
      onProgress: onProgress,
      onStatus: onStatus,
      progressStart: 0.0,
      progressEnd: 0.7,
    );
    final originalExt = prepared.extension;

    final sanitizedFileName = _sanitizeFileName(fileName);

    // Determine save directory
    String savePath;
    if (customSavePath != null && customSavePath.isNotEmpty) {
      savePath = customSavePath;
    } else {
      savePath = await _getDefaultDownloadPath();
    }

    final dir = Directory(savePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final mp3FilePath =
        '$savePath${Platform.pathSeparator}$sanitizedFileName.mp3';

    // ─── Step 2: Convert to MP3 with FFmpeg (70% → 95%) ───
    onStatus?.call('正在轉換為 MP3...');
    onProgress?.call(0.75);

    try {
      final filters = _buildAudioFilters(
        volumeMode: volumeMode,
        manualGainDb: manualGainDb,
      );
      final filterSegment =
          filters.isEmpty ? '' : ' -af "${filters.join(',')}"';
      final command =
          '-i "${prepared.filePath}" -vn$filterSegment -codec:a libmp3lame -qscale:a 2 -y "$mp3FilePath"';
      debugPrint('FFmpeg command: $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('FFmpeg conversion successful');
        onProgress?.call(0.95);

        await _deletePreparedAudioSource();

        // Verify MP3
        final mp3File = File(mp3FilePath);
        final mp3Size = await mp3File.length();
        debugPrint('MP3 size: $mp3Size bytes');

        if (mp3Size == 0) {
          await mp3File.delete();
          throw Exception('MP3 轉換後檔案為空');
        }

        onProgress?.call(1.0);
        return mp3FilePath;
      } else {
        final logs = await session.getOutput();
        debugPrint('FFmpeg failed: $logs');
        throw Exception('FFmpeg 轉換失敗');
      }
    } catch (e) {
      debugPrint('Conversion error: $e');

      // Clean up partial MP3
      final mp3File = File(mp3FilePath);
      if (await mp3File.exists()) await mp3File.delete();

      // Fallback: keep original format
      final tempFile = File(prepared.filePath);
      if (await tempFile.exists()) {
        final fallback =
            '$savePath${Platform.pathSeparator}$sanitizedFileName.$originalExt';
        await tempFile.copy(fallback);
        await tempFile.delete();
        _preparedAudioSource = null;
        onProgress?.call(1.0);
        onStatus?.call('MP3 轉換失敗，已保存為 .$originalExt');
        return fallback;
      }

      throw Exception('下載失敗: $e');
    }
  }

  Future<String> generatePreview({
    required String url,
    required VolumeAdjustmentMode volumeMode,
    required double manualGainDb,
    Function(String status)? onStatus,
  }) async {
    final normalizedGain = double.parse(manualGainDb.toStringAsFixed(1));
    if (_generatedPreview != null &&
        _generatedPreview!.url == url &&
        _generatedPreview!.mode == volumeMode &&
        _generatedPreview!.manualGainDb == normalizedGain &&
        await File(_generatedPreview!.filePath).exists()) {
      onStatus?.call('已重用預覽音訊');
      return _generatedPreview!.filePath;
    }

    final prepared = await _prepareAudioSource(
      url: url,
      onStatus: onStatus,
      progressStart: 0.0,
      progressEnd: 1.0,
    );

    await _deleteGeneratedPreview();
    onStatus?.call('正在建立預覽音訊...');

    final tempDir = await getTemporaryDirectory();
    final previewPath =
        '${tempDir.path}${Platform.pathSeparator}yt_preview_${DateTime.now().microsecondsSinceEpoch}.m4a';

    final filters = _buildAudioFilters(
      volumeMode: volumeMode,
      manualGainDb: normalizedGain,
    );
    final filterSegment =
        filters.isEmpty ? '' : ' -af "${filters.join(',')}"';
    final command =
        '-i "${prepared.filePath}" -vn$filterSegment -c:a aac -b:a 128k -ar 44100 -ac 2 -movflags +faststart -y "$previewPath"';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getOutput();
      debugPrint('Preview generation failed: $logs');
      throw Exception('無法建立預覽音訊');
    }

    final previewFile = File(previewPath);
    if (!await previewFile.exists() || await previewFile.length() == 0) {
      throw Exception('預覽音訊建立失敗');
    }

    _generatedPreview = _GeneratedPreview(
      url: url,
      filePath: previewPath,
      mode: volumeMode,
      manualGainDb: normalizedGain,
    );
    onStatus?.call('預覽音訊已準備完成');
    return previewPath;
  }

  Future<void> clearPreparedAudio() async {
    await _deleteGeneratedPreview();
    await _deletePreparedAudioSource();
  }

  Future<String?> pickSaveDirectory() async {
    try {
      return await FilePicker.platform
          .getDirectoryPath(dialogTitle: '選擇儲存位置');
    } catch (e) {
      return null;
    }
  }

  Future<String> _getDefaultDownloadPath() async {
    if (Platform.isAndroid) {
      const musicDir = '/storage/emulated/0/Music/YTDownloader';
      final dir = Directory(musicDir);
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
          return musicDir;
        } catch (_) {
          const downloadDir = '/storage/emulated/0/Download/YTDownloader';
          final dlDir = Directory(downloadDir);
          if (!await dlDir.exists()) {
            try {
              await dlDir.create(recursive: true);
              return downloadDir;
            } catch (_) {
              final appDir = await getApplicationDocumentsDirectory();
              return appDir.path;
            }
          }
          return downloadDir;
        }
      }
      return musicDir;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) return downloadsDir.path;
    }

    final appDir = await getApplicationDocumentsDirectory();
    return appDir.path;
  }

  Future<_PreparedAudioSource> _prepareAudioSource({
    required String url,
    Function(double progress)? onProgress,
    Function(String status)? onStatus,
    required double progressStart,
    required double progressEnd,
  }) async {
    if (_preparedAudioSource != null &&
        _preparedAudioSource!.url == url &&
        await File(_preparedAudioSource!.filePath).exists()) {
      onStatus?.call('已重用暫存音訊');
      onProgress?.call(progressEnd);
      return _preparedAudioSource!;
    }

    await _deletePreparedAudioSource();
    _resetClient();

    onStatus?.call('正在取得串流資訊...');
    final audioStreamInfo = await _getBestAudioStreamInfo(url);
    final originalExt = audioStreamInfo.container.name;
    debugPrint('Stream: $originalExt, ${audioStreamInfo.bitrate}bps, '
        '${audioStreamInfo.size.totalBytes} bytes');

    final tempDir = await getTemporaryDirectory();
    final tempFilePath =
        '${tempDir.path}${Platform.pathSeparator}yt_audio_${DateTime.now().microsecondsSinceEpoch}.$originalExt';

    onStatus?.call('正在下載音訊...');

    final stream = yt.videos.streams.get(audioStreamInfo);
    final tempFile = File(tempFilePath);
    final fileStream = tempFile.openWrite();

    final totalSize = audioStreamInfo.size.totalBytes;
    var downloadedBytes = 0;
    var chunkCount = 0;
    final progressRange = progressEnd - progressStart;

    try {
      await for (final chunk in stream) {
        fileStream.add(chunk);
        downloadedBytes += chunk.length;
        chunkCount++;

        if (onProgress != null) {
          if (totalSize > 0) {
            final normalized = downloadedBytes / totalSize;
            onProgress(progressStart + (normalized * progressRange));
          } else {
            final fake = 1.0 - (1.0 / (1.0 + chunkCount * 0.05));
            onProgress(progressStart + (fake * progressRange * 0.97));
          }
        }
      }
    } catch (e) {
      await fileStream.close();
      if (await tempFile.exists()) await tempFile.delete();
      throw Exception('下載中斷: $e');
    }

    await fileStream.flush();
    await fileStream.close();

    final tempSize = await tempFile.length();
    if (tempSize == 0) {
      await tempFile.delete();
      throw Exception('下載的檔案大小為 0，串流可能被封鎖');
    }
    debugPrint('Downloaded temp: $tempSize bytes');

    _preparedAudioSource = _PreparedAudioSource(
      url: url,
      filePath: tempFilePath,
      extension: originalExt,
    );
    onProgress?.call(progressEnd);
    return _preparedAudioSource!;
  }

  Future<AudioOnlyStreamInfo> _getBestAudioStreamInfo(String url) async {
    StreamManifest? manifest;
    final clientSets = [
      [YoutubeApiClient.ios, YoutubeApiClient.androidVr],
      [YoutubeApiClient.safari],
      [YoutubeApiClient.android],
      [YoutubeApiClient.tv],
    ];

    for (final clients in clientSets) {
      try {
        manifest = await yt.videos.streams.getManifest(url, ytClients: clients);
        if (manifest.audioOnly.isNotEmpty) break;
      } catch (e) {
        debugPrint('Client $clients failed: $e');
      }
    }

    if (manifest == null || manifest.audioOnly.isEmpty) {
      try {
        manifest = await yt.videos.streams.getManifest(url);
      } catch (e) {
        throw Exception('無法取得音訊串流: $e');
      }
    }

    if (manifest.audioOnly.isEmpty) {
      throw Exception('找不到可用的音訊串流');
    }

    return manifest.audioOnly.withHighestBitrate();
  }

  List<String> _buildAudioFilters({
    required VolumeAdjustmentMode volumeMode,
    required double manualGainDb,
  }) {
    switch (volumeMode) {
      case VolumeAdjustmentMode.normalize:
        return const ['loudnorm=I=-14:TP=-1.5:LRA=11'];
      case VolumeAdjustmentMode.manual:
        if (manualGainDb.abs() < 0.05) {
          return const [];
        }
        return ['volume=${manualGainDb.toStringAsFixed(1)}dB'];
      case VolumeAdjustmentMode.original:
        return const [];
    }
  }

  AudioLoudnessAnalysis? _parseLoudnessAnalysis(String output) {
    if (output.isEmpty) return null;

    final cleanedOutput = output
        .split('\n')
        .map(
          (line) => line.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '').trimRight(),
        )
        .join('\n');

    final jsonStart = cleanedOutput.indexOf('{');
    final jsonEnd = cleanedOutput.lastIndexOf('}');
    if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) {
      return null;
    }

    try {
      final jsonBlock = cleanedOutput.substring(jsonStart, jsonEnd + 1);
      final Map<String, dynamic> parsed = jsonDecode(jsonBlock);
      return AudioLoudnessAnalysis(
        integratedLufs: double.parse(parsed['input_i'] as String),
        truePeakDbtp: double.parse(parsed['input_tp'] as String),
        loudnessRange: double.parse(parsed['input_lra'] as String),
        threshold: double.parse(parsed['input_thresh'] as String),
      );
    } catch (e) {
      debugPrint('Failed to parse loudness analysis: $e');
      debugPrint(output);
      return null;
    }
  }

  Future<void> _deletePreparedAudioSource() async {
    final prepared = _preparedAudioSource;
    _preparedAudioSource = null;
    if (prepared == null) return;

    final file = File(prepared.filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _deleteGeneratedPreview() async {
    final preview = _generatedPreview;
    _generatedPreview = null;
    if (preview == null) return;

    final file = File(preview.filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void dispose() {
    _deleteGeneratedPreview();
    _deletePreparedAudioSource();
    _yt?.close();
    _yt = null;
  }
}

class _PreparedAudioSource {
  final String url;
  final String filePath;
  final String extension;

  const _PreparedAudioSource({
    required this.url,
    required this.filePath,
    required this.extension,
  });
}

class _GeneratedPreview {
  final String url;
  final String filePath;
  final VolumeAdjustmentMode mode;
  final double manualGainDb;

  const _GeneratedPreview({
    required this.url,
    required this.filePath,
    required this.mode,
    required this.manualGainDb,
  });
}

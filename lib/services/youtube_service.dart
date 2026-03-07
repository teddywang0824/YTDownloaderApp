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

  /// Downloads audio and converts to MP3.
  Future<String> downloadAudio({
    required String url,
    required String fileName,
    String? customSavePath,
    Function(double progress)? onProgress,
    Function(String status)? onStatus,
  }) async {
    _resetClient();

    onStatus?.call('正在取得串流資訊...');

    // Try multiple YouTube API clients
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
        continue;
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

    // Get the highest bitrate audio stream
    final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
    final originalExt = audioStreamInfo.container.name;
    debugPrint('Stream: $originalExt, ${audioStreamInfo.bitrate}bps, '
        '${audioStreamInfo.size.totalBytes} bytes');

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

    final tempFilePath =
        '$savePath${Platform.pathSeparator}${sanitizedFileName}_temp.$originalExt';
    final mp3FilePath =
        '$savePath${Platform.pathSeparator}$sanitizedFileName.mp3';

    // ─── Step 1: Download raw audio stream (0% → 70%) ───
    onStatus?.call('正在下載音訊...');

    final stream = yt.videos.streams.get(audioStreamInfo);
    final tempFile = File(tempFilePath);
    final fileStream = tempFile.openWrite();

    final totalSize = audioStreamInfo.size.totalBytes;
    var downloadedBytes = 0;
    var chunkCount = 0;

    try {
      await for (final chunk in stream) {
        fileStream.add(chunk);
        downloadedBytes += chunk.length;
        chunkCount++;

        if (onProgress != null) {
          if (totalSize > 0) {
            onProgress((downloadedBytes / totalSize) * 0.7);
          } else {
            final fake = 1.0 - (1.0 / (1.0 + chunkCount * 0.05));
            onProgress((fake * 0.7).clamp(0.0, 0.68));
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

    // ─── Step 2: Convert to MP3 with FFmpeg (70% → 95%) ───
    onStatus?.call('正在轉換為 MP3...');
    onProgress?.call(0.75);

    try {
      // -y = overwrite, libmp3lame = MP3 encoder, -qscale:a 2 = high quality VBR (~190kbps)
      final command =
          '-i "$tempFilePath" -vn -codec:a libmp3lame -qscale:a 2 -y "$mp3FilePath"';
      debugPrint('FFmpeg command: $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('FFmpeg conversion successful');
        onProgress?.call(0.95);

        // Delete temp file
        if (await tempFile.exists()) await tempFile.delete();

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
      if (await tempFile.exists()) {
        final fallback =
            '$savePath${Platform.pathSeparator}$sanitizedFileName.$originalExt';
        await tempFile.rename(fallback);
        onProgress?.call(1.0);
        onStatus?.call('MP3 轉換失敗，已保存為 .$originalExt');
        return fallback;
      }

      throw Exception('下載失敗: $e');
    }
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

  String _sanitizeFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void dispose() {
    _yt?.close();
    _yt = null;
  }
}

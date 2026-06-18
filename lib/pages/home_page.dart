import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';
import '../models/video_info.dart';
import '../services/youtube_service.dart';
import '../services/permission_service.dart';
import '../widgets/glowing_text_field.dart';
import '../widgets/gradient_button.dart';
import '../widgets/video_info_card.dart';
import '../widgets/download_progress_bar.dart';

class HomePage extends StatefulWidget {
  final ValueChanged<Track>? onTrackDownloaded;
  final ValueListenable<String?>? incomingSharedUrl;
  final VoidCallback? onIncomingSharedUrlConsumed;

  const HomePage({
    super.key,
    this.onTrackDownloaded,
    this.incomingSharedUrl,
    this.onIncomingSharedUrlConsumed,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _fileNameController = TextEditingController();
  final YouTubeService _ytService = YouTubeService();
  final AudioPlayer _previewPlayer = AudioPlayer();

  VideoInfo? _videoInfo;
  AudioLoudnessAnalysis? _audioAnalysis;
  DownloadProgress _downloadProgress = const DownloadProgress();
  final List<DownloadHistoryItem> _history = [];
  String? _customSavePath;
  VolumeAdjustmentMode _volumeMode = VolumeAdjustmentMode.original;
  double _manualGainDb = 0.0;
  String? _previewPath;
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;
  bool _isPreparingPreview = false;
  String? _previewError;
  bool _isDraggingPreview = false;

  StreamSubscription<Duration>? _previewPositionSub;
  StreamSubscription<Duration?>? _previewDurationSub;
  StreamSubscription<PlayerState>? _previewStateSub;
  StreamSubscription<PlayerException>? _previewErrorSub;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Request storage permissions on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissions();
    });
    unawaited(_configurePreviewAudio());

    _previewPositionSub = _previewPlayer.positionStream.listen((position) {
      if (!mounted) return;
      if (_isDraggingPreview) return;
      setState(() => _previewPosition = position);
    });
    _previewDurationSub = _previewPlayer.durationStream.listen((duration) {
      if (!mounted) return;
      setState(() => _previewDuration = duration ?? Duration.zero);
    });
    _previewStateSub = _previewPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        unawaited(_previewPlayer.seek(Duration.zero));
        unawaited(_previewPlayer.pause());
      }
      setState(() {});
    });
    _previewErrorSub = _previewPlayer.errorStream.listen((error) {
      if (!mounted) return;
      setState(() {
        _previewError = '播放器錯誤: ${error.message}';
      });
    });

    widget.incomingSharedUrl?.addListener(_handleIncomingSharedUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleIncomingSharedUrl();
    });
  }

  Future<void> _configurePreviewAudio() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await _previewPlayer.setVolume(1.0);
  }

  Future<void> _requestPermissions() async {
    final granted = await PermissionService.requestStoragePermission(context);
    if (!granted && mounted) {
      _showSnackBar('需要儲存權限才能下載音樂', isError: true);
    }
  }

  @override
  void dispose() {
    widget.incomingSharedUrl?.removeListener(_handleIncomingSharedUrl);
    _previewPositionSub?.cancel();
    _previewDurationSub?.cancel();
    _previewStateSub?.cancel();
    _previewErrorSub?.cancel();
    unawaited(_previewPlayer.dispose());
    _urlController.dispose();
    _fileNameController.dispose();
    _ytService.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incomingSharedUrl != widget.incomingSharedUrl) {
      oldWidget.incomingSharedUrl?.removeListener(_handleIncomingSharedUrl);
      widget.incomingSharedUrl?.addListener(_handleIncomingSharedUrl);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleIncomingSharedUrl();
      });
    }
  }

  Future<void> _fetchVideoInfo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showSnackBar('請輸入 YouTube 網址', isError: true);
      return;
    }

    // Validate URL
    final videoId = _ytService.extractVideoId(url);
    if (videoId == null) {
      _showSnackBar('無效的 YouTube 網址，請確認格式正確', isError: true);
      return;
    }

    // Dismiss keyboard
    FocusScope.of(context).unfocus();
    await _stopPreview();
    await _ytService.clearPreparedAudio();

    setState(() {
      _downloadProgress = const DownloadProgress(
        state: DownloadState.fetchingInfo,
        statusMessage: '正在連接 YouTube...',
      );
      _videoInfo = null;
      _audioAnalysis = null;
      _volumeMode = VolumeAdjustmentMode.original;
      _manualGainDb = 0.0;
      _previewPath = null;
      _previewPosition = Duration.zero;
      _previewDuration = Duration.zero;
      _previewError = null;
    });

    try {
      final info = await _ytService.fetchVideoInfo(url);
      setState(() {
        _videoInfo = info;
        _fileNameController.text = info.title;
        _downloadProgress = DownloadProgress(
          state: DownloadState.readyToDownload,
          statusMessage: '已取得影片資訊，下一步可分析音量',
        );
      });

      // Trigger animations
      _fadeController.reset();
      _fadeController.forward();
      _slideController.reset();
      _slideController.forward();
    } catch (e) {
      setState(() {
        _downloadProgress = DownloadProgress(
          state: DownloadState.error,
          errorMessage: '無法取得影片資訊: ${e.toString()}',
          statusMessage: '取得資訊失敗，請確認網址是否正確',
        );
      });
      _showSnackBar('取得影片資訊失敗: ${e.toString()}', isError: true);
    }
  }

  void _handleIncomingSharedUrl() {
    final sharedUrl = widget.incomingSharedUrl?.value?.trim();
    if (sharedUrl == null || sharedUrl.isEmpty) return;
    _urlController.text = sharedUrl;
    widget.onIncomingSharedUrlConsumed?.call();
    _showSnackBar('已接收分享連結', isError: false);
    unawaited(_fetchVideoInfo());
  }

  Future<void> _analyzeAudio() async {
    if (_videoInfo == null) return;

    FocusScope.of(context).unfocus();
    await _stopPreview(resetLoadedPreview: true);

    setState(() {
      _downloadProgress = const DownloadProgress(
        state: DownloadState.analyzingAudio,
        progress: 0.0,
        statusMessage: '正在準備音量分析...',
      );
    });

    try {
      final analysis = await _ytService.analyzeAudio(
        url: _videoInfo!.url,
        onProgress: (progress) {
          setState(() {
            _downloadProgress = DownloadProgress(
              state: DownloadState.analyzingAudio,
              progress: progress,
              statusMessage: progress < 0.72 ? '正在下載分析用音訊...' : '正在分析整體音量...',
            );
          });
        },
        onStatus: (status) {
          setState(() {
            _downloadProgress = _downloadProgress.copyWith(
              statusMessage: status,
            );
          });
        },
      );

      setState(() {
        _audioAnalysis = analysis;
        _volumeMode = VolumeAdjustmentMode.normalize;
        _manualGainDb = analysis.safeManualGainDb;
        _previewPath = null;
        _previewPosition = Duration.zero;
        _previewDuration = Duration.zero;
        _previewError = null;
        _downloadProgress = const DownloadProgress(
          state: DownloadState.readyToDownload,
          statusMessage: '音量分析完成，可選擇是否調整後下載',
        );
      });

      _showSnackBar('音量分析完成', isError: false);
    } catch (e) {
      setState(() {
        _downloadProgress = DownloadProgress(
          state: DownloadState.error,
          errorMessage: e.toString(),
          statusMessage: '音量分析失敗',
        );
      });
      _showSnackBar('音量分析失敗: ${e.toString()}', isError: true);
    }
  }

  Future<void> _startDownload() async {
    if (_videoInfo == null) return;
    if (_audioAnalysis == null) {
      _showSnackBar('請先分析音量，再選擇是否調整', isError: true);
      return;
    }

    final fileName = _fileNameController.text.trim();
    if (fileName.isEmpty) {
      _showSnackBar('請輸入檔案名稱', isError: true);
      return;
    }

    // Check permissions before download
    final hasPermission = await PermissionService.requestStoragePermission(context);
    if (!hasPermission) {
      if (mounted) _showSnackBar('沒有儲存權限，無法下載', isError: true);
      return;
    }

    if (!mounted) return;

    // Dismiss keyboard
    FocusScope.of(context).unfocus();
    await _stopPreview();

    setState(() {
      _downloadProgress = const DownloadProgress(
        state: DownloadState.downloading,
        progress: 0.0,
        statusMessage: '正在開始下載...',
      );
    });

    try {
      final filePath = await _ytService.downloadAudio(
        url: _videoInfo!.url,
        fileName: fileName,
        customSavePath: _customSavePath,
        volumeMode: _volumeMode,
        manualGainDb: _manualGainDb,
        onProgress: (progress) {
          setState(() {
            _downloadProgress = DownloadProgress(
              state: DownloadState.downloading,
              progress: progress,
              statusMessage: '已下載 ${(progress * 100).toInt()}%',
            );
          });
        },
        onStatus: (status) {
          setState(() {
            _downloadProgress = _downloadProgress.copyWith(
              statusMessage: status,
            );
          });
        },
      );

      setState(() {
        _downloadProgress = DownloadProgress(
          state: DownloadState.completed,
          progress: 1.0,
          filePath: filePath,
          statusMessage: '已儲存至: $filePath',
        );

        // Add to history
        _history.insert(
          0,
          DownloadHistoryItem(
            title: _videoInfo!.title,
            author: _videoInfo!.author,
            filePath: filePath,
            downloadedAt: DateTime.now(),
            thumbnailUrl: _videoInfo!.thumbnailUrl,
          ),
        );
      });

      widget.onTrackDownloaded?.call(
        Track(
          id: filePath,
          title: _videoInfo!.title,
          artist: _videoInfo!.author,
          filePath: filePath,
          duration: _videoInfo!.duration,
          addedAt: DateTime.now(),
        ),
      );

      _showSnackBar('下載完成！🎉', isError: false);
    } catch (e) {
      setState(() {
        _downloadProgress = DownloadProgress(
          state: DownloadState.error,
          errorMessage: e.toString(),
          statusMessage: '下載時發生錯誤',
        );
      });
      _showSnackBar('下載失敗: ${e.toString()}', isError: true);
    }
  }

  Future<void> _togglePreviewPlayback() async {
    if (_videoInfo == null || _audioAnalysis == null) return;

    if (_previewPlayer.playing) {
      await _previewPlayer.pause();
      final session = await AudioSession.instance;
      await session.setActive(false);
      if (mounted) setState(() {});
      return;
    }

    setState(() {
      _isPreparingPreview = true;
      _previewError = null;
    });

    try {
      final session = await AudioSession.instance;
      await session.setActive(true);

      final previewPath = await _ytService.generatePreview(
        url: _videoInfo!.url,
        volumeMode: _volumeMode,
        manualGainDb: _manualGainDb,
        onStatus: (_) {},
      );

      if (_previewPath != previewPath) {
        final duration = await _previewPlayer.setFilePath(previewPath);
        _previewPath = previewPath;
        _previewPosition = Duration.zero;
        _previewDuration = duration ?? Duration.zero;
        await _previewPlayer.seek(Duration.zero);
      }

      await _previewPlayer.play();
    } catch (e) {
      _previewError = '無法播放預覽: ${e.toString()}';
      if (mounted) {
        _showSnackBar(_previewError!, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isPreparingPreview = false);
      }
    }
  }

  Future<void> _pickSaveLocation() async {
    final path = await _ytService.pickSaveDirectory();
    if (path != null) {
      setState(() => _customSavePath = path);
      _showSnackBar('儲存路徑已更新: $path', isError: false);
    }
  }

  void _openFileLocation() {
    if (_downloadProgress.filePath != null) {
      final file = File(_downloadProgress.filePath!);
      final directory = file.parent.path;
      if (Platform.isWindows) {
        Process.run('explorer', ['/select,', _downloadProgress.filePath!]);
      } else if (Platform.isMacOS) {
        Process.run('open', [directory]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [directory]);
      } else if (Platform.isAndroid) {
        // On Android, show a dialog with the file path
        _showSnackBar('檔案已儲存至: ${_downloadProgress.filePath}', isError: false);
      }
    }
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
      _fetchVideoInfo();
    }
  }

  void _resetState() {
    unawaited(_stopPreview(resetLoadedPreview: true));
    unawaited(_ytService.clearPreparedAudio());
    setState(() {
      _urlController.clear();
      _fileNameController.clear();
      _videoInfo = null;
      _audioAnalysis = null;
      _downloadProgress = const DownloadProgress();
      _customSavePath = null;
      _volumeMode = VolumeAdjustmentMode.original;
      _manualGainDb = 0.0;
      _previewPath = null;
      _previewPosition = Duration.zero;
      _previewDuration = Duration.zero;
      _previewError = null;
    });
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: isError
            ? AppColors.error.withValues(alpha: 0.9)
            : AppColors.success.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool get _isWideScreen =>
      MediaQuery.of(context).size.width > 800;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: _isWideScreen ? _buildDesktopLayout() : _buildMobileLayout(),
      ),
    );
  }

  // ─── Desktop Layout (with sidebar) ───
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        _buildSidebar(),
        Expanded(child: _buildMainContent(horizontalPadding: 40)),
      ],
    );
  }

  // ─── Mobile Layout (no sidebar) ───
  Widget _buildMobileLayout() {
    return _buildMainContent(horizontalPadding: 20);
  }

  Widget _buildSidebar() {
    return Container(
      width: 80,
      decoration: BoxDecoration(
        gradient: AppColors.sidebarGradient,
        border: const Border(
          right: BorderSide(color: AppColors.borderLight, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Logo
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: AppColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentPurple.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 40),
          _buildNavItem(Icons.download_rounded, '下載', true),
          const SizedBox(height: 8),
          _buildNavItem(Icons.history_rounded, '紀錄', false),
          const Spacer(),
          _buildNavItem(Icons.settings_rounded, '設定', false),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String tooltip, bool isActive) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isActive
              ? AppColors.accentPurple.withValues(alpha: 0.15)
              : Colors.transparent,
          border: isActive
              ? Border.all(
                  color: AppColors.accentPurple.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Icon(
          icon,
          color: isActive ? AppColors.accentPurple : AppColors.textMuted,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildMainContent({required double horizontalPadding}) {
    return Column(
      children: [
        // Top bar
        _buildTopBar(horizontalPadding),
        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero section
                _buildHeroSection(),
                const SizedBox(height: 24),
                // URL Input section
                _buildUrlInputSection(),
                const SizedBox(height: 20),
                // Progress bar (fetching / downloading / error)
                if (_downloadProgress.state != DownloadState.idle &&
                    _downloadProgress.state !=
                        DownloadState.readyToDownload) ...[
                  DownloadProgressBar(downloadProgress: _downloadProgress),
                  const SizedBox(height: 16),
                ],
                // Video info card (shown after fetch)
                if (_videoInfo != null) ...[
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: _buildDownloadSection(),
                    ),
                  ),
                ],
                // Action buttons after completion
                if (_downloadProgress.state == DownloadState.completed) ...[
                  const SizedBox(height: 16),
                  _buildCompletionActions(),
                ],
                // History section
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildHistorySection(),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(double horizontalPadding) {
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        color: AppColors.bgPrimary.withValues(alpha: 0.8),
        border: const Border(
          bottom: BorderSide(color: AppColors.borderLight, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Logo icon (mobile only)
          if (!_isWideScreen) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: AppColors.primaryGradient,
              ),
              child: const Icon(
                Icons.music_note_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            'YT Music Downloader',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentCyan,
                  fontSize: _isWideScreen ? 18 : 16,
                ),
          ),
          const Spacer(),
          // Save location indicator (only on desktop)
          if (_isWideScreen && _customSavePath != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.bgTertiary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder_rounded,
                      color: AppColors.accentCyan, size: 16),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      _customSavePath!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return Row(
      children: [
        Icon(
          Icons.headphones_rounded,
          color: AppColors.accentCyan,
          size: _isWideScreen ? 36 : 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '下載 YouTube 音樂',
                style: _isWideScreen
                    ? Theme.of(context).textTheme.displayMedium
                    : Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '貼上 YouTube 連結，一鍵下載高品質音訊',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUrlInputSection() {
    final bool isProcessing =
        _downloadProgress.state == DownloadState.fetchingInfo ||
            _downloadProgress.state == DownloadState.analyzingAudio ||
            _downloadProgress.state == DownloadState.downloading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // URL input
        GlowingTextField(
          controller: _urlController,
          hintText: '貼上 YouTube 網址...',
          prefixIcon: Icons.link_rounded,
          enabled: !isProcessing,
          onSubmitted: (_) => _fetchVideoInfo(),
          suffixWidget: IconButton(
            onPressed: isProcessing ? null : _pasteFromClipboard,
            icon: const Icon(Icons.content_paste_rounded, size: 20),
            color: AppColors.textMuted,
            tooltip: '從剪貼簿貼上',
          ),
        ),
        const SizedBox(height: 16),
        // Action buttons row — wrap on mobile
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            GradientButton(
              text: '取得資訊',
              icon: Icons.search_rounded,
              isLoading:
                  _downloadProgress.state == DownloadState.fetchingInfo,
              onPressed: isProcessing ? null : _fetchVideoInfo,
            ),
            OutlinedButton.icon(
              onPressed: isProcessing ? null : _pickSaveLocation,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('選擇儲存位置'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.borderLight),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (_urlController.text.isNotEmpty)
              OutlinedButton.icon(
                onPressed: isProcessing ? null : _resetState,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('清除'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  side: BorderSide(
                      color: AppColors.borderLight.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadSection() {
    final isAnalyzing =
        _downloadProgress.state == DownloadState.analyzingAudio;
    final canDownload = _audioAnalysis != null && !isAnalyzing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Video info card
        VideoInfoCard(videoInfo: _videoInfo!),
        const SizedBox(height: 20),
        _buildAudioAnalysisSection(),
        const SizedBox(height: 20),
        // File name label
        Text(
          '檔案名稱',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        // File name input
        TextField(
          controller: _fileNameController,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: '輸入檔案名稱',
            prefixIcon: const Icon(
              Icons.edit_rounded,
              color: AppColors.accentCyan,
              size: 20,
            ),
            filled: true,
            fillColor: AppColors.bgTertiary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.borderLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                  color: AppColors.accentPurple, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Download button (full width on mobile)
        SizedBox(
          width: _isWideScreen ? null : double.infinity,
          child: GradientButton(
            text: canDownload ? '下載音訊' : '先分析音量',
            icon: Icons.download_rounded,
            isLoading: _downloadProgress.state == DownloadState.downloading ||
                _downloadProgress.state == DownloadState.analyzingAudio,
            onPressed: _downloadProgress.state == DownloadState.downloading ||
                    _downloadProgress.state == DownloadState.analyzingAudio
                ? null
                : canDownload
                    ? _startDownload
                    : _analyzeAudio,
          ),
        ),
      ],
    );
  }

  Widget _buildAudioAnalysisSection() {
    final isProcessing = _downloadProgress.state == DownloadState.fetchingInfo ||
        _downloadProgress.state == DownloadState.analyzingAudio ||
        _downloadProgress.state == DownloadState.downloading;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.borderLight.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.graphic_eq_rounded,
                color: AppColors.accentCyan,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                '音量分析',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: isProcessing ? null : _analyzeAudio,
                icon: const Icon(Icons.analytics_rounded, size: 16),
                label: Text(_audioAnalysis == null ? '分析音量' : '重新分析'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentCyan,
                  side: const BorderSide(color: AppColors.borderLight),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_audioAnalysis == null) ...[
            Text(
              '會先下載暫存音訊並量測整體 loudness，再讓你決定要保留原始音量、做標準化，或手動微調。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
          ] else ...[
            _buildAnalysisMetrics(),
            const SizedBox(height: 14),
            Text(
              _audioAnalysis!.summary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildVolumeModeOption(
                  mode: VolumeAdjustmentMode.original,
                  title: '原始音量',
                  subtitle: '不做任何處理',
                ),
                _buildVolumeModeOption(
                  mode: VolumeAdjustmentMode.normalize,
                  title: '自動標準化',
                  subtitle: '目標 -14 LUFS',
                ),
                _buildVolumeModeOption(
                  mode: VolumeAdjustmentMode.manual,
                  title: '手動微調',
                  subtitle: '自行調整 dB',
                ),
              ],
            ),
            if (_volumeMode == VolumeAdjustmentMode.manual) ...[
              const SizedBox(height: 16),
              _buildManualGainControl(),
            ],
            const SizedBox(height: 16),
            _buildPreviewSection(),
            if (_volumeMode == VolumeAdjustmentMode.normalize) ...[
              const SizedBox(height: 12),
              Text(
                '系統會把輸出音量拉近常見串流平台的聽感，通常最適合處理忽大忽小的歌曲。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisMetrics() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildMetricPill(
          '整體音量',
          '${_audioAnalysis!.integratedLufs.toStringAsFixed(1)} LUFS',
        ),
        _buildMetricPill(
          '峰值',
          '${_audioAnalysis!.truePeakDbtp.toStringAsFixed(1)} dBTP',
        ),
        _buildMetricPill(
          '動態範圍',
          '${_audioAnalysis!.loudnessRange.toStringAsFixed(1)} LU',
        ),
        _buildMetricPill(
          '建議微調',
          '${_audioAnalysis!.safeManualGainDb >= 0 ? '+' : ''}${_audioAnalysis!.safeManualGainDb.toStringAsFixed(1)} dB',
        ),
      ],
    );
  }

  Widget _buildMetricPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgTertiary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderLight.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeModeOption({
    required VolumeAdjustmentMode mode,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _volumeMode == mode;

    return InkWell(
      onTap: () {
        unawaited(_invalidatePreviewForSettingsChange());
        setState(() {
          _volumeMode = mode;
          if (mode == VolumeAdjustmentMode.manual && _audioAnalysis != null) {
            _manualGainDb = _audioAnalysis!.safeManualGainDb;
          }
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: _isWideScreen ? 170 : null,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentPurple.withValues(alpha: 0.14)
              : AppColors.bgTertiary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.accentPurple.withValues(alpha: 0.7)
                : AppColors.borderLight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection() {
    final isPreviewPlaying = _previewPlayer.playing;
    final previewMax = _previewDuration > Duration.zero
        ? _previewDuration
        : (_videoInfo?.duration ?? Duration.zero);
    final clampedPosition = _previewPosition > previewMax
        ? previewMax
        : _previewPosition;
    final sliderMax =
        previewMax.inMilliseconds <= 0 ? 1.0 : previewMax.inMilliseconds.toDouble();
    final sliderValue = clampedPosition.inMilliseconds
        .toDouble()
        .clamp(0.0, sliderMax);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgTertiary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.borderLight.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.play_circle_outline_rounded,
                color: AppColors.accentCyan,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                '音量預覽',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '會播放套用目前設定後的整首預覽音訊，方便你直接確認音量調整的效果。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              GradientButton(
                text: isPreviewPlaying ? '暫停預覽' : '播放預覽',
                icon: isPreviewPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                isLoading: _isPreparingPreview,
                onPressed: _isPreparingPreview ? null : _togglePreviewPlayback,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.accentPurple,
                        inactiveTrackColor: AppColors.bgPrimary,
                        thumbColor: AppColors.accentCyan,
                        overlayColor:
                            AppColors.accentCyan.withValues(alpha: 0.12),
                        trackHeight: 6,
                      ),
                      child: Slider(
                        value: sliderValue,
                        min: 0,
                        max: sliderMax,
                        onChanged: _previewPath == null
                            ? null
                            : (value) {
                                setState(() {
                                  _isDraggingPreview = true;
                                  _previewPosition =
                                      Duration(milliseconds: value.round());
                                });
                              },
                        onChangeStart: _previewPath == null
                            ? null
                            : (_) {
                                setState(() => _isDraggingPreview = true);
                              },
                        onChangeEnd: _previewPath == null
                            ? null
                            : (value) async {
                                await _previewPlayer.seek(
                                  Duration(milliseconds: value.round()),
                                );
                                if (!mounted) return;
                                setState(() => _isDraggingPreview = false);
                              },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // IconButton(
                        //   onPressed: _previewPath == null
                        //       ? null
                        //       : () => _seekPreviewBy(const Duration(seconds: -5)),
                        //   icon: const Icon(
                        //     Icons.replay_5_rounded,
                        //     color: AppColors.textSecondary,
                        //   ),
                        //   tooltip: '倒退 5 秒',
                        // ),
                        // IconButton(
                        //   onPressed: _previewPath == null
                        //       ? null
                        //       : () => _seekPreviewBy(const Duration(seconds: 5)),
                        //   icon: const Icon(
                        //     Icons.forward_5_rounded,
                        //     color: AppColors.textSecondary,
                        //   ),
                        //   tooltip: '快轉 5 秒',
                        // ),
                        const Spacer(),
                        Text(
                          _previewPlayer.playing ? '播放中' : '已暫停',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          _formatDurationCompact(clampedPosition),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDurationCompact(previewMax),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_previewError != null) ...[
            const SizedBox(height: 10),
            Text(
              _previewError!,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManualGainControl() {
    final safeManualGain = _audioAnalysis!.safeManualGainDb.clamp(-12.0, 16.0);
    final minGain = -12.0;
    final maxGain = 16.0;
    final clampedGain = _manualGainDb.clamp(minGain, maxGain).toDouble();
    final exceedsRecommended = clampedGain > safeManualGain + 0.05;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '手動調整',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const Spacer(),
            Text(
              '${clampedGain >= 0 ? '+' : ''}${clampedGain.toStringAsFixed(1)} dB',
              style: const TextStyle(
                color: AppColors.accentCyan,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.accentPurple,
            inactiveTrackColor: AppColors.bgPrimary,
            thumbColor: AppColors.accentCyan,
            overlayColor: AppColors.accentCyan.withValues(alpha: 0.12),
          ),
          child: Slider(
            value: clampedGain,
            min: minGain,
            max: maxGain,
            onChangeStart: (_) {
              unawaited(_invalidatePreviewForSettingsChange());
            },
            onChanged: (value) {
              setState(() => _manualGainDb = value);
            },
          ),
        ),
        Text(
          '建議值: ${safeManualGain >= 0 ? '+' : ''}${safeManualGain.toStringAsFixed(1)} dB',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          exceedsRecommended
              ? '目前已超過建議增益，雖然可以更大聲，但比較容易失真或爆音。'
              : _audioAnalysis!.manualBoostLimitedByPeak
                  ? '建議值已依峰值做保守限制。想整體拉大聲時，仍可繼續往上調，但要留意失真。'
                  : '手動模式會直接調整輸出音量，負值更小聲，正值更大聲。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: exceedsRecommended
                    ? AppColors.warning
                    : AppColors.textMuted,
                height: 1.5,
              ),
        ),
      ],
    );
  }

  Future<void> _invalidatePreviewForSettingsChange() async {
    await _stopPreview(resetLoadedPreview: true);
    if (!mounted) return;
    setState(() {
      _previewPath = null;
      _previewPosition = Duration.zero;
      _previewDuration = Duration.zero;
      _previewError = null;
    });
  }

  Future<void> _stopPreview({bool resetLoadedPreview = false}) async {
    await _previewPlayer.pause();
    await _previewPlayer.seek(Duration.zero);
    final session = await AudioSession.instance;
    await session.setActive(false);
    if (resetLoadedPreview) {
      await _previewPlayer.stop();
    }
  }

  Future<void> _seekPreviewBy(Duration delta) async {
    final duration = _previewDuration;
    final current = _previewPosition;
    var target = current + delta;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (duration > Duration.zero && target > duration) {
      target = duration;
    }
    await _previewPlayer.seek(target);
    if (!mounted) return;
    setState(() => _previewPosition = target);
  }

  String _formatDurationCompact(Duration duration) {
    if (duration == Duration.zero) return '00:00';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildCompletionActions() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        GradientButton(
          text: '開啟檔案位置',
          icon: Icons.folder_open_rounded,
          onPressed: _openFileLocation,
        ),
        OutlinedButton.icon(
          onPressed: _resetState,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('下載其他音樂'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accentCyan,
            side: const BorderSide(color: AppColors.accentCyan),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.history_rounded,
              color: AppColors.accentCyan,
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              '下載紀錄',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...List.generate(
          _history.length.clamp(0, 10),
          (index) => _buildHistoryItem(_history[index]),
        ),
      ],
    );
  }

  Widget _buildHistoryItem(DownloadHistoryItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgSecondary,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: [
                  AppColors.accentPurple.withValues(alpha: 0.2),
                  AppColors.accentCyan.withValues(alpha: 0.1),
                ],
              ),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: AppColors.accentPurple,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.author} • ${_formatTime(item.downloadedAt)}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 18,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
    if (diff.inHours < 24) return '${diff.inHours} 小時前';
    return '${dateTime.month}/${dateTime.day} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

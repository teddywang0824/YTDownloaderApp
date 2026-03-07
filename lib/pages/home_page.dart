import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/video_info.dart';
import '../services/youtube_service.dart';
import '../services/permission_service.dart';
import '../widgets/glowing_text_field.dart';
import '../widgets/gradient_button.dart';
import '../widgets/video_info_card.dart';
import '../widgets/download_progress_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _fileNameController = TextEditingController();
  final YouTubeService _ytService = YouTubeService();

  VideoInfo? _videoInfo;
  DownloadProgress _downloadProgress = const DownloadProgress();
  final List<DownloadHistoryItem> _history = [];
  String? _customSavePath;

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
  }

  Future<void> _requestPermissions() async {
    final granted = await PermissionService.requestStoragePermission(context);
    if (!granted && mounted) {
      _showSnackBar('需要儲存權限才能下載音樂', isError: true);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _fileNameController.dispose();
    _ytService.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
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

    setState(() {
      _downloadProgress = const DownloadProgress(
        state: DownloadState.fetchingInfo,
        statusMessage: '正在連接 YouTube...',
      );
      _videoInfo = null;
    });

    try {
      final info = await _ytService.fetchVideoInfo(url);
      setState(() {
        _videoInfo = info;
        _fileNameController.text = info.title;
        _downloadProgress = DownloadProgress(
          state: DownloadState.readyToDownload,
          statusMessage: '已取得影片資訊，準備下載',
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

  Future<void> _startDownload() async {
    if (_videoInfo == null) return;

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
    setState(() {
      _urlController.clear();
      _fileNameController.clear();
      _videoInfo = null;
      _downloadProgress = const DownloadProgress();
      _customSavePath = null;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Video info card
        VideoInfoCard(videoInfo: _videoInfo!),
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
            text: '下載音訊',
            icon: Icons.download_rounded,
            isLoading: _downloadProgress.state == DownloadState.downloading,
            onPressed: _downloadProgress.state == DownloadState.downloading
                ? null
                : _startDownload,
          ),
        ),
      ],
    );
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

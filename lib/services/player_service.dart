import 'dart:async';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';

class PlayerService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<PlayerException>? _errorSub;

  Track? _currentTrack;
  List<Track> _playbackQueue = const [];
  double Function(String trackId)? _gainForTrack;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPreparing = false;
  bool _isPlaying = false;
  bool _isAdvancingTrack = false;
  String? _errorMessage;
  double _currentGainDb = 0.0;

  Track? get currentTrack => _currentTrack;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPreparing => _isPreparing;
  bool get isPlaying => _isPlaying;
  String? get errorMessage => _errorMessage;
  double get currentGainDb => _currentGainDb;

  Future<void> initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _positionSub = _player.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });
    _durationSub = _player.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });
    _playerStateSub = _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      if (state.processingState == ProcessingState.completed) {
        if (hasNext(_playbackQueue)) {
          unawaited(_handlePlaybackCompleted());
        } else {
          _position = Duration.zero;
        }
      }
      notifyListeners();
    });
    _errorSub = _player.errorStream.listen((error) {
      _errorMessage = error.message;
      notifyListeners();
    });
  }

  Future<void> playTrack(
    Track track, {
    double gainDb = 0.0,
    List<Track>? queue,
    double Function(String trackId)? gainForTrack,
  }) async {
    _isPreparing = true;
    _errorMessage = null;
    _updatePlaybackQueue(queue, gainForTrack);
    notifyListeners();

    try {
      final session = await AudioSession.instance;
      await session.setActive(true);

      final shouldReload = _currentTrack?.filePath != track.filePath;
      _currentTrack = track;
      _currentGainDb = gainDb;

      if (shouldReload) {
        final loadedDuration = await _player.setFilePath(track.filePath);
        _duration = loadedDuration ?? track.duration ?? Duration.zero;
        _position = Duration.zero;
      } else if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
        _position = Duration.zero;
      }

      await _applyGain(gainDb);
      unawaited(_resumePlayback());
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isPreparing = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayback() async {
    if (_currentTrack == null || _isPreparing) return;

    if (_isPlaying) {
      await pause();
      return;
    }

    final session = await AudioSession.instance;
    await session.setActive(true);

    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
      _position = Duration.zero;
    }

    unawaited(_resumePlayback());
    notifyListeners();
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> seek(Duration target) async {
    await _player.seek(target);
    _position = target;
    notifyListeners();
  }

  Future<void> seekBy(Duration delta) async {
    final total = _duration;
    var target = _position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;
    await seek(target);
  }

  bool hasPrevious(List<Track> tracks) {
    return _canNavigateQueue(tracks);
  }

  bool hasNext(List<Track> tracks) {
    return _canNavigateQueue(tracks);
  }

  Future<void> playPrevious(
    List<Track> tracks, {
    required double Function(String trackId) gainForTrack,
  }) async {
    _updatePlaybackQueue(tracks, gainForTrack);
    final index = _neighborIndex(tracks, direction: -1, wrap: true);
    if (index == null) return;

    final track = tracks[index];
    await playTrack(
      track,
      gainDb: gainForTrack(track.id),
      queue: tracks,
      gainForTrack: gainForTrack,
    );
  }

  Future<void> playNext(
    List<Track> tracks, {
    required double Function(String trackId) gainForTrack,
  }) async {
    _updatePlaybackQueue(tracks, gainForTrack);
    final index = _neighborIndex(tracks, direction: 1, wrap: true);
    if (index == null) return;

    final track = tracks[index];
    await playTrack(
      track,
      gainDb: gainForTrack(track.id),
      queue: tracks,
      gainForTrack: gainForTrack,
    );
  }

  Future<void> setTrackGainDb(double gainDb) async {
    _currentGainDb = gainDb;
    await _applyGain(gainDb);
    notifyListeners();
  }

  Future<void> _applyGain(double gainDb) async {
    final linear =
        pow(10, gainDb / 20).toDouble().clamp(0.05, 8.0).toDouble();
    await _player.setVolume(linear);
  }

  void _updatePlaybackQueue(
    List<Track>? queue,
    double Function(String trackId)? gainForTrack,
  ) {
    if (queue != null) {
      _playbackQueue = List.unmodifiable(queue);
    }
    if (gainForTrack != null) {
      _gainForTrack = gainForTrack;
    }
  }

  bool _canNavigateQueue(List<Track> tracks) {
    if (_currentTrack == null || tracks.length <= 1) return false;
    return tracks.indexWhere((track) => track.id == _currentTrack!.id) != -1;
  }

  int? _neighborIndex(
    List<Track> tracks, {
    required int direction,
    bool wrap = false,
  }) {
    if (_currentTrack == null || tracks.isEmpty) return null;

    final currentIndex = tracks.indexWhere((track) => track.id == _currentTrack!.id);
    if (currentIndex == -1) return null;

    final targetIndex = currentIndex + direction;
    if (targetIndex < 0) {
      return wrap ? tracks.length - 1 : null;
    }
    if (targetIndex >= tracks.length) {
      return wrap ? 0 : null;
    }

    return targetIndex;
  }

  Future<void> _handlePlaybackCompleted() async {
    if (_isAdvancingTrack || _gainForTrack == null) return;

    _isAdvancingTrack = true;
    try {
      await playNext(
        _playbackQueue,
        gainForTrack: _gainForTrack!,
      );
    } finally {
      _isAdvancingTrack = false;
    }
  }

  Future<void> _resumePlayback() async {
    try {
      await _player.play();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> disposeService() async {
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playerStateSub?.cancel();
    await _errorSub?.cancel();
    final session = await AudioSession.instance;
    await session.setActive(false);
    await _player.dispose();
  }
}

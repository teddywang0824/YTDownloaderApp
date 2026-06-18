import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

class LibraryService extends ChangeNotifier {
  static const String _tracksKey = 'library_tracks_v1';
  static const String _gainKey = 'library_track_gain_v1';

  final List<Track> _tracks = [];
  final Map<String, double> _trackGainDb = {};
  SharedPreferences? _prefs;
  bool _isLoaded = false;

  List<Track> get tracks => List.unmodifiable(_tracks);
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _tracks
      ..clear()
      ..addAll(_loadTracks());
    _trackGainDb
      ..clear()
      ..addAll(_loadGainMap());
    _isLoaded = true;
    notifyListeners();
  }

  double gainForTrack(String trackId) {
    return _trackGainDb[trackId] ?? 0.0;
  }

  Future<void> addOrUpdateTrack(Track track) async {
    final index = _tracks.indexWhere((item) => item.id == track.id);
    if (index == -1) {
      _tracks.insert(0, track);
    } else {
      _tracks[index] = track;
      final updated = _tracks.removeAt(index);
      _tracks.insert(0, updated);
    }
    await _persistTracks();
    notifyListeners();
  }

  Future<void> setTrackGain(String trackId, double gainDb) async {
    _trackGainDb[trackId] = gainDb;
    await _persistGainMap();
    notifyListeners();
  }

  Future<void> removeTrack(String trackId) async {
    _tracks.removeWhere((track) => track.id == trackId);
    _trackGainDb.remove(trackId);
    await _persistTracks();
    await _persistGainMap();
    notifyListeners();
  }

  Future<Track?> importLocalTrack() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'opus', 'webm'],
    );

    final pickedPath = result?.files.single.path;
    if (pickedPath == null || pickedPath.isEmpty) {
      return null;
    }

    final file = File(pickedPath);
    if (!await file.exists()) {
      return null;
    }

    final fileName = file.path.split(Platform.pathSeparator).last;
    final dotIndex = fileName.lastIndexOf('.');
    final title = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;

    final track = Track(
      id: file.path,
      title: title,
      artist: '本機匯入',
      filePath: file.path,
      addedAt: DateTime.now(),
    );
    await addOrUpdateTrack(track);
    return track;
  }

  List<Track> _loadTracks() {
    final raw = _prefs?.getString(_tracksKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, double> _loadGainMap() {
    final raw = _prefs?.getString(_gainKey);
    if (raw == null || raw.isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );
    } catch (_) {
      return const {};
    }
  }

  Future<void> _persistTracks() async {
    await _prefs?.setString(
      _tracksKey,
      jsonEncode(_tracks.map((track) => track.toJson()).toList()),
    );
  }

  Future<void> _persistGainMap() async {
    await _prefs?.setString(_gainKey, jsonEncode(_trackGainDb));
  }
}

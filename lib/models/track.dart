class Track {
  final String id;
  final String title;
  final String artist;
  final String filePath;
  final Duration? duration;
  final DateTime addedAt;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.filePath,
    this.duration,
    required this.addedAt,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Unknown Title',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      filePath: json['filePath'] as String,
      duration: json['durationMs'] == null
          ? null
          : Duration(milliseconds: json['durationMs'] as int),
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'filePath': filePath,
      'durationMs': duration?.inMilliseconds,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? filePath,
    Duration? duration,
    DateTime? addedAt,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      filePath: filePath ?? this.filePath,
      duration: duration ?? this.duration,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}

import 'dart:async';

import 'package:flutter/services.dart';

class IncomingShareService {
  static const EventChannel _shareStreamChannel =
      EventChannel('yt_downloader/share_stream');

  Stream<String> sharedTextStream() {
    return _shareStreamChannel
        .receiveBroadcastStream()
        .where((event) => event is String && event.trim().isNotEmpty)
        .cast<String>();
  }
}

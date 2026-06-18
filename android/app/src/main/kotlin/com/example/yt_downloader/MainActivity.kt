package com.example.yt_downloader

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var sharedTextSink: EventChannel.EventSink? = null
    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_STREAM_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sharedTextSink = events
                pendingSharedText?.let {
                    sharedTextSink?.success(it)
                    pendingSharedText = null
                }
            }

            override fun onCancel(arguments: Any?) {
                sharedTextSink = null
            }
        })

        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return

        if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            if (!sharedText.isNullOrEmpty()) {
                if (sharedTextSink != null) {
                    sharedTextSink?.success(sharedText)
                } else {
                    pendingSharedText = sharedText
                }
            }
        }
    }

    companion object {
        private const val SHARE_STREAM_CHANNEL = "yt_downloader/share_stream"
    }
}

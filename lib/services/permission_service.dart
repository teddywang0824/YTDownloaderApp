import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Handles runtime permission requests for Android.
class PermissionService {
  /// Requests all necessary permissions for downloading files.
  /// Returns true if all required permissions are granted.
  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (!Platform.isAndroid) return true; // Desktop doesn't need runtime permissions

    // Android 13+ (API 33): use granular media permissions
    // Android 11-12 (API 30-32): use MANAGE_EXTERNAL_STORAGE
    // Android 10 and below (API ≤ 29): use WRITE_EXTERNAL_STORAGE

    final androidInfo = await _getAndroidSdkVersion();

    if (androidInfo >= 33) {
      // Android 13+: request audio permission
      final status = await Permission.audio.request();
      if (status.isGranted) return true;

      // Also try manage external storage for broader access
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;

      if (status.isPermanentlyDenied || manageStatus.isPermanentlyDenied) {
        if (context.mounted) {
          _showPermissionDeniedDialog(context);
        }
        return false;
      }
      return false;
    } else if (androidInfo >= 30) {
      // Android 11-12: use MANAGE_EXTERNAL_STORAGE
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        if (context.mounted) {
          _showPermissionDeniedDialog(context);
        }
        return false;
      }
      return false;
    } else {
      // Android 10 and below
      final status = await Permission.storage.request();
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        if (context.mounted) {
          _showPermissionDeniedDialog(context);
        }
        return false;
      }
      return false;
    }
  }

  /// Checks if storage permissions are already granted.
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await _getAndroidSdkVersion();

    if (androidInfo >= 33) {
      return await Permission.audio.isGranted ||
          await Permission.manageExternalStorage.isGranted;
    } else if (androidInfo >= 30) {
      return await Permission.manageExternalStorage.isGranted;
    } else {
      return await Permission.storage.isGranted;
    }
  }

  /// Gets the Android SDK version from system properties.
  static Future<int> _getAndroidSdkVersion() async {
    try {
      // Read from Android build properties
      final versionString = Platform.operatingSystemVersion;
      // Try to parse SDK version from the OS version string
      // Fallback: assume API 30+ if we can't determine
      final match = RegExp(r'API (\d+)').firstMatch(versionString);
      if (match != null) {
        return int.parse(match.group(1)!);
      }
    } catch (_) {}
    // Conservative default: assume Android 11+ (API 30)
    return 30;
  }

  /// Shows a dialog when the user has permanently denied permissions.
  static void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.folder_off_rounded, color: Color(0xFFF59E0B), size: 24),
            SizedBox(width: 10),
            Text(
              '需要儲存權限',
              style: TextStyle(color: Color(0xFFF1F1F6), fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          '下載音樂需要存取裝置儲存空間。\n請前往設定頁面手動開啟權限。',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('前往設定', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

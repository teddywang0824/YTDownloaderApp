# YT Music Downloader

A cross-platform Flutter application designed to download audio from YouTube videos and seamlessly convert them into high-quality MP3 files directly on your Android device.

## App Icon
![App Icon](assets/icon.png)

## Summary
YT Music Downloader provides a clean, modern, and ad-free experience for downloading YouTube audio. Built with Flutter, the application leverages FFmpeg for reliable native audio conversion. It automatically handles Android storage permissions across various API levels, supports direct YouTube share-in on Android, and lets users preview and adjust playback volume before downloading.

Current release target: `v1.0.1`

## Key Features
- **URL Parsing and Metadata Fetching:** Instantly retrieves video title, author, duration, and high-resolution thumbnails.
- **Native MP3 Conversion:** Downloads raw webm/opus audio streams and converts them to 190kbps VBR MP3 using a robust native FFmpeg implementation (`ffmpeg_kit_flutter_new`).
- **Volume Analysis and Preview:** Measures loudness, previews the processed result, and supports original / normalized / manual output volume.
- **Built-in Player and Library:** Saves downloaded tracks into the in-app library and supports play, pause, seek, previous/next, looped queue playback, and per-track volume memory.
- **Android Share Integration:** Lets users share a YouTube link directly from the YouTube app into this app without manually pasting the URL.
- **Automated Storage Management:** Automatically creates necessary directories and requests correct runtime permissions (supporting Android 10, 11-12, and 13+ granular media permissions).
- **Responsive Navigation and UI:** Features a sleek dark theme, glassmorphism UI elements, and real-time visual progress tracking without blocking the main render thread.

## Installation for Users
To install the application on your Android device:
1. Go to the **Releases** section of this repository.
2. Download the latest `app-release.apk` file.
3. Open the downloaded file on your Android device. You may need to enable "Install from Unknown Sources" in your device settings.
4. Follow the on-screen prompts to install the application.

## Usage Guide
1. Launch the YT Music application.
2. Upon first launch, allow the app to access your device's storage.
3. Copy a valid YouTube video link and paste it into the URL input field, or share the link directly from the YouTube app into this app.
4. Press Enter or click the search icon to fetch the video details. The app will display the video thumbnail, title, author, and duration.
5. Run loudness analysis if you want to compare source volume, normalization, or manual gain.
6. Preview the audio and adjust the output volume if needed.
7. Provide a custom file name in the designated text field, or leave it to use the default video title.
8. Click the download button.
9. Monitor the progress bar as the app downloads the audio stream and converts it.
10. Once completed, your new MP3 file will be available in the `Music/YTDownloader` folder on your internal storage, and the track will also be available in the in-app player/library.

## Project Structure

```text
yt_downloader/
├── android/            # Android native configurations (Permissions, ProGuard, Gradle)
├── assets/             # Application assets and generated launcher icons
├── ios/                # iOS native configurations
├── lib/                # Main Flutter application code
│   ├── models/         # Data structures and state definitions (VideoInfo, Progress)
│   ├── pages/          # Application screens (HomePage)
│   ├── services/       # Core business logic
│   │   ├── permission_service.dart   # Cross-version Android permission handling
│   │   └── youtube_service.dart      # Download stream extraction and FFmpeg logic
│   ├── theme/          # Centralized theme control and color palettes
│   ├── widgets/        # Reusable UI components (VideoInfoCard, ProgressBar)
│   └── main.dart       # Application entry point
├── pubspec.yaml        # Project dependencies (youtube_explode_dart, ffmpeg_kit)
└── README.md           # Project documentation
```

## Development Setup
If you wish to build or modify the app yourself:

1. Ensure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
2. Clone this repository.
3. Navigate to the project root and install dependencies:
   ```bash
   flutter pub get
   ```
4. Run the application in debug mode:
   ```bash
   flutter run
   ```
5. To build a release APK (with ProGuard rules automatically applied):
   ```bash
   flutter build apk --release
   ```

## Release Workflow
This project currently publishes Android release files through GitHub Releases.

1. Confirm the app version in `pubspec.yaml`.
   For the next release, this project is now set to:
   ```yaml
   version: 1.0.1+2
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Build the Android release APK:
   ```bash
   flutter build apk --release
   ```
4. The generated file will be located at:
   ```text
   build/app/outputs/flutter-apk/app-release.apk
   ```
5. Commit your changes and push them to GitHub.
6. Create and push the release tag:
   ```bash
   git tag v1.0.1
   git push origin main
   git push origin v1.0.1
   ```
7. In GitHub, open the repository's **Releases** page and create a new release from tag `v1.0.1`.
8. Upload `app-release.apk` as the release asset.
9. Add release notes describing the main user-facing changes.

Suggested release title:
```text
v1.0.1
```

Suggested release assets:
- `app-release.apk`

Suggested release notes:
- Added in-app player controls with play, pause, seek, previous, and next.
- Added looped queue playback for downloaded tracks.
- Added per-track volume memory and preview-based loudness adjustment.
- Added Android share target support for receiving YouTube links directly from the YouTube app.

## Android Release Note
The current Android release build is configured in:
`android/app/build.gradle.kts`

At the moment, the `release` build type is still signed with the debug signing key so local release APK generation works quickly:
```kotlin
signingConfig = signingConfigs.getByName("debug")
```

This is acceptable for internal testing or simple GitHub APK distribution, but before a more formal public distribution you should replace it with your own release keystore.

## Dependencies
This project relies on the following major packages:
- `youtube_explode_dart`: For parsing YouTube pages and extracting stream manifests.
- `ffmpeg_kit_flutter_new`: Full GPL version of FFmpegKit for highly reliable command-line based audio conversion.
- `permission_handler`: For cross-version runtime Android permission handling.
- `file_picker` & `path_provider`: For directory resolution and path generation.

# YT Music Downloader

A cross-platform Flutter application designed to download audio from YouTube videos and seamlessly convert them into high-quality MP3 files directly on your Android device.

## App Icon
![App Icon](assets/icon.png)

## Summary
YT Music Downloader provides a clean, modern, and ad-free experience for downloading YouTube audio. Built with Flutter, the application leverages FFmpeg for reliable native audio conversion. It automatically handles Android storage permissions across various API levels, ensuring downloaded files are saved safely into your device's `Music/YTDownloader` directory. 

## Key Features
- **URL Parsing and Metadata Fetching:** Instantly retrieves video title, author, duration, and high-resolution thumbnails.
- **Native MP3 Conversion:** Downloads raw webm/opus audio streams and converts them to 190kbps VBR MP3 using a robust native FFmpeg implementation (`ffmpeg_kit_flutter_new`).
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
3. Copy a valid YouTube video link and paste it into the URL input field.
4. Press Enter or click the search icon to fetch the video details. The app will display the video thumbnail, title, author, and duration.
5. Provide a custom file name in the designated text field, or leave it to use the default video title.
6. Click the **"Download MP3"** button.
7. Monitor the progress bar as the app downloads the audio stream and converts it. 
8. Once completed, your new MP3 file will be available in the `Music/YTDownloader` folder on your internal storage.

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

## Dependencies
This project relies on the following major packages:
- `youtube_explode_dart`: For parsing YouTube pages and extracting stream manifests.
- `ffmpeg_kit_flutter_new`: Full GPL version of FFmpegKit for highly reliable command-line based audio conversion.
- `permission_handler`: For cross-version runtime Android permission handling.
- `file_picker` & `path_provider`: For directory resolution and path generation.

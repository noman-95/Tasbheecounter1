# Free Tajweed engine — Android test setup

The project is now wired to `recite_quran ^1.0.3` for live on-device word alignment and deterministic Tajweed timing checks.

## One-time setup

From the project folder on a PC with Flutter/Dart installed:

```bash
flutter pub get
dart run recite_quran:download_model
flutter pub get
flutter build apk --release
```

The package documentation says the command downloads the ~72 MB INT8 Zipformer model to `assets/model/` and adds it to `pubspec.yaml`.

Then install the generated APK on the phone.

## Test checklist

1. Open an Ayah.
2. Press mic and recite normally.
3. Watch words change live: green = matched, orange = Tajweed timing warning, red = skipped/mispronounced.
4. Stop the mic.
5. Confirm the colors remain after leaving and reopening the Ayah.
6. Make one word red, press mic again, and recite only that word. The previous correct words must stay unchanged.
7. Test Madd and Mushaddad Ghunnah words.
8. Test quiet background noise and normal room speech.

## Important audio note

For Quranic phoneme recognition, the package intentionally avoids aggressive system noise suppression/auto-gain because these can remove subtle sounds such as `هـ` and `ح`. The microphone stream is therefore kept clean and raw rather than applying a generic speech-recorder noise filter.

## License

Keep the Quran-Lab NPL-1.2 license with the distributed work. Do not add ads, subscriptions, paywalls, or paid features that depend on this engine. Automatic Tajweed feedback can be wrong and is not a replacement for a qualified teacher.

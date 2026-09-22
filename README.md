# Quran Recitation — V9 Self-Hosted Online Tajweed

This build removes the paid QRC API requirement. Recitation analysis is sent to a **self-hosted Sanad** backend; no API key is embedded in the APK.

## App

```bash
flutter pub get
flutter build apk --release --dart-define=SANAD_BASE_URL=http://YOUR_PC_LAN_IP:8000
```

For Android emulator the default is `http://10.0.2.2:8000`.

## Backend

See `server_setup/README.md` and run `server_setup/setup_sanad_windows.ps1` on the computer that will host the Tajweed engine.

The mobile app requires internet/Wi-Fi access to that server for recitation analysis. Quran/history remain local.

## Scope

Sanad is open-source AGPL-3.0. Its current published engine measures **madd duration and ghunnah/nasality**, plus word/content scoring. It is not a complete real-time 11-rule Tajweed judge and its authors document CPU inference taking seconds per ayah and limited validation. Treat feedback as assistive practice, not a scholarly ruling.

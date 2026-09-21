# Tasbheecounter

The existing Zikr/Tasbih screens and storage are kept from the previous working project.

Added Quran features:
- Quran Learning screen with 114 Surahs.
- Arabic Quran text from the bundled Tanzil SQL asset.
- Urdu translation from the bundled Urdu JSON asset.
- Ayah-by-ayah Quran reading screen.
- AI Recitation Check using the microphone.
- Recitation is evaluated after the whole ayah/session ends, not word-by-word during live speaking.
- Correct words are shown in green and wrong words in red.
- Left button = Next; right button = Previous.

Before running:

```bash
flutter clean
flutter pub get
flutter run -d chrome
```

For Android release:

```bash
flutter build apk --release
```

Offline Quran Audio:
- Surah screen has an "Offline Surah Audio" download button.
- Recitation screen has "Sunain" and "Offline Save" controls.
- Audio is downloaded per ayah and stored inside the app; downloaded ayahs can then be played without internet.
- The first download requires internet.
- Recite & Check remains separate: playing the Qari audio is optional, and feedback still runs after the full ayah is recited.
- Chrome/web can stream the reference audio but cannot use the local offline download cache.

Important offline note:
- Offline Qari audio is supported after the ayah/surah audio has been downloaded once.
- The current `speech_to_text` feedback engine uses the device speech-recognition service, so its ability to work with no internet depends on the installed Arabic speech service/language pack. The app does not claim guaranteed fully-offline AI speech grading yet.

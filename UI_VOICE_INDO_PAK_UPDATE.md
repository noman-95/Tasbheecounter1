# Mobile Premium UI + Voice + Script Update

- Mobile-first premium Quran Learning / Recitation UI pass.
- Urdu translation content/layout preserved.
- Quran script selector persisted as Uthmani or Indo-Pak.
- Surah and Recitation Arabic font follows selected script.
- Android/iOS recitation now prefers the bundled OfflineAsrService (Sherpa/Whisper Quran model) and falls back to speech_to_text if the model cannot start.
- First mobile use can download the offline Quran voice model with visible progress.
- Quran progress only advances after an attempt reaches 80% word accuracy; failed attempts remain in history/feedback.
- Web/Chrome continues to use speech_to_text as a development fallback because the offline recorder/model is not supported on web.

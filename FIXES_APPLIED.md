# TasbheeCounter - Quran UI / Recitation fixes

Updated for the current Quran learning prototype.

## Changes

- Registered the Uthmanic Hafs font and Indo-Pak font in `pubspec.yaml`.
- Quran Arabic display now uses `UthmanicHafs1Ver18.ttf`, so Uthmani diacritics and waqf/recitation marks present in the source text can render correctly.
- Improved recitation word alignment with sequence alignment instead of simple positional matching.
- Added Arabic normalization for common alif/hamza/taa marbuta/yaa variants and Quran annotation marks.
- Added three visual feedback states: green = correct, orange = improve, red = wrong.
- Redesigned the recitation screen with a cleaner Quran-learning layout, progress bar, ayah card, Urdu translation card, word chips, audio controls, recording area, and Previous/Next navigation.
- Applied the Uthmanic font to Arabic ayah display in the Surah screen as well.

## Important limitation

The online/device speech recognition package is still used for the current live microphone path. Word-level matching is improved, but this is not a Tajweed-grade phoneme/AI evaluator. The project already contains an optional offline Sherpa/Whisper ASR service; connecting that as the primary Android recitation engine can be done as the next step for stronger recognition.


## Current patch (2026-09-22)

- Prevented late/stale speech-recognition callbacks from adding words after the microphone is stopped.
- Added a blocking first-time Quran Voice AI download screen with progress and disabled app interaction while the model is downloading.
- Improved Arabic normalization for Quran-script variants while keeping harakat/recitation marks available for separate checking.
- Quran ayah word-status history is stored per Surah + Ayah without duplicate records and is restored automatically when that ayah is opened again.
- Added a compact mobile home layout for short phone viewports so the main screen does not require scrolling.
- Added an explicit limitation: text ASR cannot by itself verify acoustic Tajweed such as makhraj, ghunnah, madd and qalqalah.

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

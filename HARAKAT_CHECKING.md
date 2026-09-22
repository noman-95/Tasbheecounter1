# Harakat-aware recitation checking

This version preserves the existing tolerant Arabic word matching and adds a
conservative harakat check.

- Word/letter matching still uses `_normalizeArabic()`.
- When the speech recognizer returns Arabic diacritics (zabar, zer, pesh,
  sukun, shadda, tanwin and Quranic marks in the configured Unicode range),
  the matched word's marks are compared with the Quran reference.
- A confirmed mark mismatch changes an otherwise-correct word to `wrong`.
- If the speech recognizer omits diacritics, the app does **not** mark the
  word red solely because of missing marks. Text-only ASR cannot prove that
  the user pronounced a particular harakat incorrectly.
- Existing retry and history behavior is preserved.

This is not acoustic Tajweed verification of makhraj, madd, ghunnah,
qalqalah, etc. Those require a pronunciation/acoustic model.

# V9 — Self-hosted online Tajweed

Paid QRC API dependency removed. The Flutter app now records one ayah and POSTs a 16-kHz mono WAV to a configurable self-hosted Sanad backend (`/grade`).

The backend returns `word_scores` with green/yellow/red verdicts plus measured Tajweed rule results. History stays on-device.

**Important:** Sanad's current published scope is calibrated mainly for madd and ghunnah, uses Wav2Vec2 forced alignment, and can take seconds per ayah on CPU. It should not be described as a complete real-time Tajweed authority.

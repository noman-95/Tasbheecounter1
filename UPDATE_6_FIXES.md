# Update 6 — Voice, performance and mobile fixes

Applied to the example-style project:

1. **Retry no longer resets the whole ayah.** When an ayah has red/orange words, starting the mic preserves the existing word-status list and only re-evaluates those target words.
2. **Late mic results blocked.** A session token invalidates stale speech callbacks after Stop, preventing a random word from being inserted after the mic is turned off.
3. **Noise/echo control kept enabled.** Offline recording uses 16 kHz mono WAV with echo cancellation, noise suppression and automatic gain control.
4. **Offline ASR performance improved.** Sherpa-ONNX CPU decoder uses 4 threads instead of 2.
5. **Main screen is responsive without a mandatory ScrollView.** Compact vertical spacing is used on short phone displays.
6. **Online recognition remains the first path.** The phone's online Arabic speech recognizer is used before the downloaded offline Quran model. Word matching still happens locally. True cloud Tajweed scoring (makhraj/madd/ghunnah acoustic analysis) requires a Tajweed-capable backend/API; the app does not pretend that text-only ASR can measure those acoustic properties.
7. **History persistence remains Surah + Ayah keyed.** Word colors are restored when the same ayah is reopened.

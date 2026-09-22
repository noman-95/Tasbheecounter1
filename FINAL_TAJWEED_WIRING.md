# Final free Tajweed wiring

This build uses `recite_quran ^1.0.3` as the live on-device engine. It connects:

Mic -> 16 kHz PCM -> Zipformer CTC -> phoneme/DTW alignment -> word events -> Madd/Ghunnah/Shaddah Tajweed timing -> saved green/orange/red history.

The package documentation says the engine supports real-time word tracking, deterministic Tajweed checks for Madd, Mushaddad Ghunnah and Shaddah, and on-device processing. It also provides `AudioProcessor` and a background alignment isolate.

## Model setup

From the Flutter project root, run:

```bash
dart run recite_quran:download_model
flutter pub get
flutter build apk --release
```

The downloader places the INT8 Zipformer model in `assets/model/` and updates `pubspec.yaml` as documented by the package.

If your environment does not have the downloader available, request access to the upstream Quran-Lab model and obtain the model under its NPL-1.2 terms. The upstream model is gated and requires accepting its access conditions.

## Important license rule

The app must remain completely free. Do not add AdMob/ads, subscriptions, paywalls, or paid Tajweed features when distributing this model/derivative. Keep the NPL-1.2 license with the distributed work and show a clear notice that automatic Tajweed feedback can be wrong and does not replace a qualified teacher.

## What is now wired

- Live microphone PCM directly into the Tajweed engine.
- No `speech_to_text` result is used for the primary Tajweed path.
- Green = matched word.
- Orange = matched word with Tajweed timing diagnostic.
- Red = skipped/mispronounced word.
- Previous correct words remain saved when retrying a failed word.
- Single failed word can be focused without clearing the entire ayah state.
- History is upserted by Surah + Ayah and stores every word's status.

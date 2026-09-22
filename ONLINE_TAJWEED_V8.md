# V8 — Online-first Tajweed

This build intentionally removes the offline AI/Tajweed path from recitation checking.
The recitation screen uses Qurani.ai QRC as the authoritative live analysis engine.

## Test build

Provide the API key at build/run time:

```bash
flutter pub get
flutter run --dart-define=QRC_API_KEY=YOUR_KEY
```

For a release build:

```bash
flutter build apk --release --dart-define=QRC_API_KEY=YOUR_KEY
```

Also supported:

```bash
--dart-define=QRC_WS_URL=wss://api.qurani.ai
```

## Important

QRC currently requires a subscription/API key according to the official documentation. Do not put a production API key directly into source control. A mobile client can expose a key to a determined attacker; for production, use a small authenticated backend/proxy that owns the QRC credential.

The app now:

- requires internet + QRC configuration for recitation checking;
- does not fall back to generic speech-to-text or the previous offline model;
- keeps existing word colors when a new microphone session starts;
- merges overlapping QRC result windows instead of replacing the entire ayah with pending states;
- persists word history continuously with a debounce;
- stops audio capture before sending RESET so the final audio tail can be flushed;
- disables aggressive recorder noise suppression/auto-gain to preserve Arabic phonetic/Tajweed cues;
- treats QRC's word/tajweed/letter result as authoritative and does not run the old local evaluator afterward.

QRC result mapping:

- skipped_words -> red/wrong
- tajweed_mistakes or letter_mistakes -> orange/review
- correct_words without matching mistakes -> green/correct

See the official QRC documentation for subscription/API details and the WebSocket + MessagePack contract.

# Free Advanced Tajweed mode

This project is prepared for a **free, no-ads, no-subscription** on-device Tajweed pipeline using the Quran-Lab Zipformer phoneme model and sherpa-onnx.

## Model

Quran-Lab `zipformer_p_arabic_v3.1.int8.onnx` is a streaming CTC model whose phonetic alphabet encodes Tajweed-relevant distinctions including madd, ghunna, ikhfa, qalqalah and emphatic consonants.

Model page:
https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3

The model repository is gated. The developer must request/accept access on Hugging Face before downloading its files. The app source does **not** bypass that gate and does not contain credentials.

Required files:
- `zipformer_p_arabic_v3.1.int8.onnx`
- `tokens.txt`

Place them in the app's private directory:
`free_tajweed_model/`

## License requirement

Quran-Lab NPL-1.2 is a no-profit license. The model and features powered by it must not be sold, put behind subscriptions/paywalls, or monetized with advertising. The license file must be retained with the distributed derivative.

The model page also requires the application to state that automatic Tajweed feedback can be wrong and does not replace a qualified teacher.

## Important engineering note

The current app keeps the paid QRC client as an optional fallback, but the intended production path for this free app is the local phoneme engine. The adapter in `lib/services/free_tajweed_service.dart` uses sherpa-onnx's streaming Zipformer2-CTC API. The next integration step is to feed the recorder's 16-kHz PCM chunks into that adapter and compare its phoneme stream against the canonical Quran phoneme sequence for each ayah.

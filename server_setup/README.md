# Free/self-hosted Tajweed backend

This project uses the open-source **Sanad** Tajweed correction engine instead of a paid API.
Sanad is AGPL-3.0 and currently measures two objectively calibrated rule families: **madd (duration)** and **ghunnah (duration + nasality)**. It also produces word-level content verdicts. It is **not** a complete 11-rule real-time Tajweed judge, and its own README says CPU inference takes seconds per ayah and it is not validated across learner voices. Do not market the result as a replacement for a qualified teacher.

Repository: https://github.com/harounRhim/sanad

## Windows

Run `setup_sanad_windows.ps1` from this folder. It clones Sanad, creates a Python environment and installs requirements.

Before first server start, download the Hugging Face model into the environment cache while internet is enabled. The server then runs with its offline-cache mode so inference does not repeatedly contact Hugging Face.

Example:

```powershell
cd sanad
$env:HF_HOME="$PWD/.hf_cache"
$env:HF_HUB_OFFLINE="0"
python -c "from transformers import AutoProcessor, AutoModelForCTC; m='jonatasgrosman/wav2vec2-large-xlsr-53-arabic'; AutoProcessor.from_pretrained(m); AutoModelForCTC.from_pretrained(m)"
$env:HF_HUB_OFFLINE="1"
$env:TRANSFORMERS_OFFLINE="1"
python -m uvicorn server.app:app --host 0.0.0.0 --port 8000
```

## Android phone

If the phone and PC are on the same Wi-Fi, build with your PC's LAN address:

```bash
flutter build apk --release --dart-define=SANAD_BASE_URL=http://192.168.1.10:8000
```

Replace `192.168.1.10` with the PC's LAN IP.

For an Android emulator, the default `http://10.0.2.2:8000` is already configured.

## Important licensing/cost

The Sanad code is AGPL-3.0. Its README says modified network services must publish those modifications. Qur'anic text, Tajweed annotations and reciter audio have separate terms; review `DATA_SOURCES.md` before redistribution. The software itself has no paid API key, but a public 24/7 server may have hosting costs.

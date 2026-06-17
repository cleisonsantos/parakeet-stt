# Parakeet V3 STT Provider for Hermes Agent 🎤

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Model: CC-BY-4.0](https://img.shields.io/badge/Model-CC--BY--4.0-lightgrey)](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)

A [Hermes Agent](https://hermes-agent.nousresearch.com/) plugin that adds
**NVIDIA Parakeet-TDT-0.6B-v3** as a speech-to-text provider — a 600M-parameter
multilingual ASR model that runs efficiently on **CPU** with automatic language
detection for 25 European languages, including **Portuguese**.

---

## 🚀 Install with one command

Copy and paste this into your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/cleisonsantos/parakeet-stt/main/install.sh | bash
```

The script will:

1. ✅ Detect if Hermes is installed (aborts with instructions if not)
2. ✅ Find your Hermes installation directory and Python venv
3. ✅ Clone the plugin to the right `plugins/` folder
4. ✅ Enable the plugin via `hermes plugins enable`
5. ✅ Install Python dependencies (transformers, torch, etc.)
6. ✅ Verify everything is in place
7. ✅ Show you the final config step

### Install for a specific profile

```bash
curl -fsSL https://raw.githubusercontent.com/cleisonsantos/parakeet-stt/main/install.sh | bash -s -- --profile sureka-cloud
```

---

## Why Parakeet V3?

| Aspect | faster-whisper large-v3 (default) | Parakeet V3 |
|--------|-----------------------------------|-------------|
| **Parameters** | ~1.5B | **600M** |
| **CPU inference** | Very slow (10-30s) | **Fast (~1-2s)** |
| **GPU inference** | Fast (~0.5s) | Fast (~0.3s) |
| **Language detection** | ❌ Manual | ✅ **Automatic** |
| **Model size (disk)** | ~3GB | **~600MB** |
| **RAM usage** | ~3GB | **~1.5GB** |
| **Languages** | 100+ | 25 (European) |

> ✅ **Best for**: CPU-only machines, Portuguese speakers, low-RAM environments
> ⚠️ **Limited to 25 European languages** — not suitable for Asian/African languages

---

## Manual Setup

If you prefer to install step by step:

### 1. Clone the plugin

```bash
git clone https://github.com/cleisonsantos/parakeet-stt.git ~/.hermes/plugins/parakeet-stt

# For a named profile:
# git clone https://github.com/cleisonsantos/parakeet-stt.git ~/.hermes/profiles/<name>/plugins/parakeet-stt
```

### 2. Install dependencies

```bash
# Find your Hermes venv (usually ~/.hermes/hermes-agent/.venv or venv)
uv pip install --python /path/to/hermes/venv/bin/python3 \
  transformers torch soundfile librosa accelerate
```

### 3. Enable the plugin

```bash
hermes plugins enable parakeet-stt
```

### 4. Configure

Edit your profile's `config.yaml`:

```yaml
stt:
  provider: parakeet          # ← switch to Parakeet V3
  # provider: local           # ← faster-whisper (default)
  parakeet:
    language: ""              # auto-detect; "pt" for Portuguese
```

### 5. Restart the gateway

```bash
hermes gateway restart
```

---

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `stt.provider` | Set to `parakeet` to activate | `local` |
| `stt.parakeet.language` | BCP-47 hint (`"pt"`, `"en"`, or `""` for auto) | `""` |

---

## Testing

Send a voice message on any connected platform (Telegram, Discord, etc.)
and check the gateway logs:

```bash
tail -f ~/.hermes/logs/gateway.log | grep -i parakeet
```

You should see:

```
parakeet_stt: Loading Parakeet-TDT-0.6B-v3 on cpu...
parakeet_stt: Parakeet-TDT-0.6B-v3 loaded successfully on cpu
parakeet_stt: Transcribing audio_xxx.ogg with Parakeet V3 (lang: auto)...
parakeet_stt: Transcribed audio_xxx.ogg with Parakeet V3 (NN chars)
```

Or test directly from Python:

```bash
HERMES_HOME=~/.hermes /path/to/hermes/venv/bin/python3 -c "
import sys; sys.path.insert(0, '/path/to/hermes-agent')
from hermes_cli.plugins import _ensure_plugins_discovered
from agent.transcription_registry import list_providers
_ensure_plugins_discovered()
p = next(pv for pv in list_providers() if pv.name == 'parakeet')
r = p.transcribe('/path/to/audio.wav')
print(r.get('transcript', ''))
"
```

---

## Switching Back to faster-whisper

```yaml
stt:
  provider: local    # ← change back
```

Then restart the gateway.

---

## How It Works

This plugin implements Hermes's `TranscriptionProvider` ABC
(`agent.transcription_provider.TranscriptionProvider`) and registers
it via `ctx.register_transcription_provider()` at discovery time.

The model (`nvidia/parakeet-tdt-0.6b-v3`) is:
- **Loaded lazily** — only on the first `transcribe()` call
- **Cached as a singleton** — subsequent calls reuse the loaded pipeline
- **Device-aware** — auto-selects CUDA → MPS → CPU
- **Auto-chunking** — splits audio >30s into segments
- **Weight ~600MB** — downloaded once and cached in `~/.cache/huggingface/hub/`

### Project Structure

```
parakeet-stt/
├── plugin.yaml       # Hermes plugin manifest
├── __init__.py       # TranscriptionProvider implementation
├── install.sh        # One-command installer (auto-detects Hermes)
├── README.md         # This file
├── LICENSE           # MIT license
└── .gitignore
```

---

## License

- **Plugin code**: MIT (see [LICENSE](LICENSE))
- **Parakeet-TDT-0.6B-v3 model**: [CC-BY-4.0](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)

Built with [Hermes Agent](https://hermes-agent.nousresearch.com/) by
[Nous Research](https://nousresearch.com/).

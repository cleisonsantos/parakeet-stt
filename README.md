# Parakeet V3 STT Provider for Hermes Agent 🎤

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Model: CC-BY-4.0](https://img.shields.io/badge/Model-CC--BY--4.0-lightgrey)](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)

A [Hermes Agent](https://hermes-agent.nousresearch.com/) plugin that adds
**NVIDIA Parakeet-TDT-0.6B-v3** as a speech-to-text provider — a 600M-parameter
multilingual ASR model that runs efficiently on **CPU** with automatic language
detection for 25 European languages, including **Portuguese**.

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

## Quick Install

### Prerequisites

- [Hermes Agent](https://hermes-agent.nousresearch.com/) installed
- Python dependencies (install in the Hermes venv):

```bash
cd /path/to/hermes-agent
uv pip install transformers torch soundfile librosa accelerate
```

### Install the plugin

```bash
# Clone this repo into your Hermes plugins directory
mkdir -p ~/.hermes/plugins
git clone https://github.com/cleisonsantos/parakeet-stt.git ~/.hermes/plugins/parakeet-stt

# Or using the install script:
curl -fsSL https://raw.githubusercontent.com/cleisonsantos/parakeet-stt/main/install.sh | bash
```

### Enable the plugin

```bash
hermes plugins enable parakeet-stt
```

### Switch to Parakeet V3

Edit `~/.hermes/config.yaml` (or your profile's config.yaml):

```yaml
stt:
  provider: parakeet          # ← switch to Parakeet V3
  # provider: local           # ← faster-whisper (default)
  parakeet:
    language: ""              # auto-detect; "pt" for Portuguese
```

Then restart the gateway:

```bash
hermes gateway restart
```

## Manual Setup

If you prefer to install manually:

1. **Copy the plugin files** to your Hermes profile:

```bash
# For the default profile:
cp -r parakeet-stt ~/.hermes/plugins/parakeet-stt

# For a named profile:
cp -r parakeet-stt ~/.hermes/profiles/<profile>/plugins/parakeet-stt
```

2. **Enable** the plugin:
```bash
hermes plugins enable parakeet-stt
```

3. **Install dependencies** in the Hermes venv:
```bash
cd /path/to/hermes-agent
uv pip install transformers torch soundfile librosa accelerate
```

4. **Configure** `stt.provider: parakeet` in your config.yaml

5. **Restart** the gateway:
```bash
hermes gateway restart
```

## Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `stt.provider` | Set to `parakeet` to activate | `local` |
| `stt.parakeet.language` | BCP-47 language hint (`"pt"`, `"en"`, or empty for auto-detect) | `""` |

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

## Switching Back to faster-whisper

```yaml
stt:
  provider: local    # ← change back
```

Then restart the gateway.

## Project Structure

```
parakeet-stt/
├── plugin.yaml       # Hermes plugin manifest
├── __init__.py       # TranscriptionProvider implementation
├── install.sh        # One-command install script
├── README.md         # This file
├── LICENSE           # MIT license
└── .gitignore
```

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

## License

- **Plugin code**: MIT (see [LICENSE](LICENSE))
- **Parakeet-TDT-0.6B-v3 model**: [CC-BY-4.0](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)

Built with [Hermes Agent](https://hermes-agent.nousresearch.com/) by
[Nous Research](https://nousresearch.com/).

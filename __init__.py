"""
Parakeet-TDT-0.6B-v3 Speech-to-Text Provider for Hermes Agent
===============================================================

A :class:`~agent.transcription_provider.TranscriptionProvider` that wraps
NVIDIA's Parakeet-TDT-0.6B-v3 — a 600M-parameter multilingual ASR model
based on FastConformer-TDT architecture. CPU-optimized, supports 25 European
languages (including Portuguese) with **automatic language detection**.

Usage
-----
Once installed and enabled, switch to this provider in config.yaml::

    stt:
      provider: parakeet
      parakeet:
        language: ""       # auto-detect; "pt" for Portuguese

Then restart the gateway::

    hermes gateway restart

Dependencies
------------
- ``transformers`` (>=4.50)
- ``torch``
- ``soundfile``, ``librosa``
- ``accelerate`` (optional)
- ``ffmpeg`` on PATH (for ogg/mp3 transcoding)

Install them in the Hermes venv::

    uv pip install transformers torch soundfile librosa accelerate
"""

from __future__ import annotations

import logging
import os
import subprocess
import warnings
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Lazy model singleton — loaded once, reused across calls
# ---------------------------------------------------------------------------
_parakeet_pipeline = None  # singleton pipeline
_parakeet_device = None


def _check_ffmpeg() -> bool:
    """Check if ffmpeg is available on PATH (needed for non-WAV formats)."""
    try:
        subprocess.run(
            ["ffmpeg", "-version"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except (FileNotFoundError, OSError):
        return False


def _get_parakeet_pipeline():
    """Return the singleton Parakeet ASR pipeline.

    Loads the model on first call and caches it for the lifetime of the
    Hermes agent process. This is critical for performance — model loading
    takes ~2–30s, but inference takes ~0.5–2s per short clip.
    """
    global _parakeet_pipeline, _parakeet_device

    if _parakeet_pipeline is not None:
        return _parakeet_pipeline

    try:
        import torch
        from transformers import pipeline as hf_pipeline
    except ImportError as exc:
        raise ImportError(
            "Parakeet STT requires 'transformers' and 'torch'. "
            "Install with: "
            "uv pip install transformers torch soundfile librosa accelerate"
        ) from exc

    # Check ffmpeg
    if not _check_ffmpeg():
        logger.warning(
            "ffmpeg not found on PATH. Parakeet V3 may fail to transcode "
            "non-WAV formats (ogg, mp3). Install ffmpeg for full support."
        )

    os.environ.setdefault("HF_HUB_DISABLE_SYMBOLS_WARNING", "1")

    # Pick the best available device
    if torch.cuda.is_available():
        device = "cuda:0"
    elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        device = "mps"
    else:
        device = "cpu"

    _parakeet_device = device
    model_id = "nvidia/parakeet-tdt-0.6b-v3"

    logger.info(
        "Loading Parakeet-TDT-0.6B-v3 on %s (this may take 10–30s)...",
        device,
    )

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            _parakeet_pipeline = hf_pipeline(
                "automatic-speech-recognition",
                model=model_id,
                device=device,
            )
        logger.info("Parakeet-TDT-0.6B-v3 loaded successfully on %s", device)
    except Exception as exc:
        _parakeet_pipeline = None
        raise RuntimeError(
            f"Failed to load Parakeet-TDT-0.6B-v3: {exc}\n\n"
            "If you see 'unknown architecture' or 'not supported', you may "
            "need a newer transformers version:\n"
            "  pip install git+https://github.com/huggingface/transformers"
        ) from exc

    return _parakeet_pipeline


def _unload_parakeet_pipeline():
    """Force-unload the pipeline (for testing / config changes)."""
    global _parakeet_pipeline, _parakeet_device
    _parakeet_pipeline = None
    _parakeet_device = None
    import gc
    gc.collect()
    try:
        import torch
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except ImportError:
        pass


# ---------------------------------------------------------------------------
# Provider Implementation
# ---------------------------------------------------------------------------


class ParakeetTranscriptionProvider:
    """Transcription provider using NVIDIA Parakeet-TDT-0.6B-v3.

    The model is loaded once (lazily on first ``transcribe()`` call) and
    cached as a module-level singleton so subsequent calls reuse it.
    """

    @property
    def name(self) -> str:
        return "parakeet"

    @property
    def display_name(self) -> str:
        return "Parakeet V3 (NVIDIA)"

    def is_available(self) -> bool:
        try:
            import transformers  # noqa: F401
            import torch        # noqa: F401
            return True
        except ImportError:
            return False

    def list_models(self) -> List[Dict[str, Any]]:
        return [
            {
                "id": "nvidia/parakeet-tdt-0.6b-v3",
                "display": "Parakeet-TDT-0.6B-v3",
                "languages": [
                    "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr",
                    "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt",
                    "ro", "sk", "sl", "es", "sv", "ru", "uk",
                ],
                "max_audio_seconds": 1440,
            }
        ]

    def default_model(self) -> Optional[str]:
        return "nvidia/parakeet-tdt-0.6b-v3"

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "Parakeet V3 (NVIDIA)",
            "badge": "local",
            "tag": "CPU-optimized local STT, 25 languages",
            "env_vars": [],
        }

    def transcribe(
        self,
        file_path: str,
        *,
        model: Optional[str] = None,
        language: Optional[str] = None,
        **extra: Any,
    ) -> Dict[str, Any]:
        """Transcribe audio using Parakeet-TDT-0.6B-v3.

        Args:
            file_path: Absolute path to audio file.
            model: Ignored — single pre-trained model.
            language: Optional BCP-47 hint (e.g. ``"pt"``, ``"en"``).
                Auto-detects language when not provided.

        Returns:
            Standard transcription envelope dict.
        """
        audio_path = Path(file_path)
        if not audio_path.exists():
            return {
                "success": False,
                "transcript": "",
                "error": f"Audio file not found: {file_path}",
                "provider": "parakeet",
            }

        try:
            pipe = _get_parakeet_pipeline()
        except (ImportError, RuntimeError) as exc:
            return {
                "success": False,
                "transcript": "",
                "error": str(exc),
                "provider": "parakeet",
            }

        logger.info(
            "Transcribing %s with Parakeet V3 (lang: %s)...",
            audio_path.name,
            language or "auto",
        )

        try:
            file_size = audio_path.stat().st_size
            use_chunking = file_size > 500_000  # ~30s of 16kHz mono

            pipe_kwargs = {"return_timestamps": False}
            if use_chunking:
                pipe_kwargs["chunk_length_s"] = 30

            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                result = pipe(str(audio_path.resolve()), **pipe_kwargs)

            transcript = ""
            if isinstance(result, dict):
                transcript = result.get("text", "")
            elif isinstance(result, str):
                transcript = result
            elif isinstance(result, list):
                texts = []
                for chunk in result:
                    if isinstance(chunk, dict):
                        texts.append(chunk.get("text", ""))
                    elif isinstance(chunk, str):
                        texts.append(chunk)
                transcript = " ".join(texts)

            transcript = transcript.strip()
            if not transcript:
                return {
                    "success": False,
                    "transcript": "",
                    "error": "Parakeet V3 returned empty transcript",
                    "provider": "parakeet",
                }

            logger.info(
                "Transcribed %s with Parakeet V3 (%d chars)",
                audio_path.name,
                len(transcript),
            )

            return {
                "success": True,
                "transcript": transcript,
                "provider": "parakeet",
            }

        except Exception as exc:
            logger.warning(
                "Parakeet V3 transcription failed: %s", exc, exc_info=True
            )
            return {
                "success": False,
                "transcript": "",
                "error": f"Parakeet V3 STT failed: {exc}",
                "provider": "parakeet",
            }


# ---------------------------------------------------------------------------
# Plugin entry point
# ---------------------------------------------------------------------------


def register(ctx) -> None:
    """Register the Parakeet V3 transcription provider with Hermes.

    Called by the Hermes plugin system at discovery time.
    After registration, configure via ``stt.provider: parakeet`` in config.yaml
    to use it as the active STT backend.
    """
    from agent.transcription_provider import TranscriptionProvider

    # Dynamically inherit from the ABC so the plugin system
    # recognises this as a valid TranscriptionProvider.
    provider_cls = type(
        "RegisteredParakeetProvider",
        (ParakeetTranscriptionProvider, TranscriptionProvider),
        {},
    )
    provider = provider_cls()
    ctx.register_transcription_provider(provider)
    logger.info(
        "Parakeet V3 STT plugin registered. Use stt.provider='parakeet' in config.yaml"
    )

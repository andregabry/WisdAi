"""Clean Apache-2.0 / MIT Sherpa-ONNX TTS backend for OpenJarvis (Supertonic-3 & Kokoro-int8, zero PyTorch/GPL)."""

from __future__ import annotations

import ctypes
import io
import logging
import os
import threading
import wave
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np
from openjarvis.core.registry import TTSRegistry
from openjarvis.speech.tts import TTSBackend, TTSResult

logger = logging.getLogger(__name__)


def _normalize_brand_pronunciation(text: str, language: str) -> str:
    is_en = (language or "").lower().startswith("en")
    replacements = (
        ("WisdMeet", "Wisd Meet" if is_en else "Uísd Mit"),
        ("WisdFin", "Wisd Fin" if is_en else "Uísd Fin"),
        ("WisdAI", "Wisd A I" if is_en else "Uísd Êi Ai"),
    )
    out = text.strip()
    for src, dst in replacements:
        out = out.replace(src, dst)
    return out


class _VitsCfg(ctypes.Structure):
    _fields_ = [
        ("model", ctypes.c_char_p),
        ("lexicon", ctypes.c_char_p),
        ("tokens", ctypes.c_char_p),
        ("data_dir", ctypes.c_char_p),
        ("noise_scale", ctypes.c_float),
        ("noise_scale_w", ctypes.c_float),
        ("length_scale", ctypes.c_float),
        ("dict_dir", ctypes.c_char_p),
    ]


class _MatchaCfg(ctypes.Structure):
    _fields_ = [
        ("acoustic_model", ctypes.c_char_p),
        ("vocoder", ctypes.c_char_p),
        ("lexicon", ctypes.c_char_p),
        ("tokens", ctypes.c_char_p),
        ("data_dir", ctypes.c_char_p),
        ("noise_scale", ctypes.c_float),
        ("length_scale", ctypes.c_float),
        ("dict_dir", ctypes.c_char_p),
    ]


class _KokoroCfg(ctypes.Structure):
    _fields_ = [
        ("model", ctypes.c_char_p),
        ("voices", ctypes.c_char_p),
        ("tokens", ctypes.c_char_p),
        ("data_dir", ctypes.c_char_p),
        ("length_scale", ctypes.c_float),
        ("dict_dir", ctypes.c_char_p),
        ("lexicon", ctypes.c_char_p),
        ("lang", ctypes.c_char_p),
    ]


class _KittenCfg(ctypes.Structure):
    _fields_ = [
        ("model", ctypes.c_char_p),
        ("voices", ctypes.c_char_p),
        ("tokens", ctypes.c_char_p),
        ("data_dir", ctypes.c_char_p),
        ("length_scale", ctypes.c_float),
    ]


class _ZipvoiceCfg(ctypes.Structure):
    _fields_ = [
        ("tokens", ctypes.c_char_p),
        ("encoder", ctypes.c_char_p),
        ("decoder", ctypes.c_char_p),
        ("vocoder", ctypes.c_char_p),
        ("data_dir", ctypes.c_char_p),
        ("lexicon", ctypes.c_char_p),
        ("feat_scale", ctypes.c_float),
        ("t_shift", ctypes.c_float),
        ("target_rms", ctypes.c_float),
        ("guidance_scale", ctypes.c_float),
    ]


class _PocketCfg(ctypes.Structure):
    _fields_ = [
        ("lm_flow", ctypes.c_char_p),
        ("lm_main", ctypes.c_char_p),
        ("encoder", ctypes.c_char_p),
        ("decoder", ctypes.c_char_p),
        ("text_conditioner", ctypes.c_char_p),
        ("vocab_json", ctypes.c_char_p),
        ("token_scores_json", ctypes.c_char_p),
        ("voice_embedding_cache_capacity", ctypes.c_int32),
    ]


class _SupertonicCfg(ctypes.Structure):
    _fields_ = [
        ("duration_predictor", ctypes.c_char_p),
        ("text_encoder", ctypes.c_char_p),
        ("vector_estimator", ctypes.c_char_p),
        ("vocoder", ctypes.c_char_p),
        ("tts_json", ctypes.c_char_p),
        ("unicode_indexer", ctypes.c_char_p),
        ("voice_style", ctypes.c_char_p),
    ]


class _ModelCfg(ctypes.Structure):
    _fields_ = [
        ("vits", _VitsCfg),
        ("num_threads", ctypes.c_int32),
        ("debug", ctypes.c_int32),
        ("provider", ctypes.c_char_p),
        ("matcha", _MatchaCfg),
        ("kokoro", _KokoroCfg),
        ("kitten", _KittenCfg),
        ("zipvoice", _ZipvoiceCfg),
        ("pocket", _PocketCfg),
        ("supertonic", _SupertonicCfg),
    ]


class _TtsCfg(ctypes.Structure):
    _fields_ = [
        ("model", _ModelCfg),
        ("rule_fsts", ctypes.c_char_p),
        ("max_num_sentences", ctypes.c_int32),
        ("rule_fars", ctypes.c_char_p),
        ("silence_scale", ctypes.c_float),
    ]


class _GeneratedAudio(ctypes.Structure):
    _fields_ = [
        ("samples", ctypes.POINTER(ctypes.c_float)),
        ("n", ctypes.c_int32),
        ("sample_rate", ctypes.c_int32),
    ]


class _GenCfg(ctypes.Structure):
    _fields_ = [
        ("silence_scale", ctypes.c_float),
        ("speed", ctypes.c_float),
        ("sid", ctypes.c_int32),
        ("reference_audio", ctypes.POINTER(ctypes.c_float)),
        ("reference_audio_len", ctypes.c_int32),
        ("reference_sample_rate", ctypes.c_int32),
        ("reference_text", ctypes.c_char_p),
        ("num_steps", ctypes.c_int32),
        ("extra", ctypes.c_char_p),
    ]


_SUPERTONIC_SPEAKERS: Dict[str, int] = {
    "supertonic:f1": 0,
    "supertonic:f2": 1,
    "supertonic:f3": 2,
    "supertonic:f4": 3,
    "supertonic:f5": 4,
    "supertonic:m1": 5,
    "supertonic:m2": 6,
    "supertonic:m3": 7,
    "supertonic:m4": 8,
    "supertonic:m5": 9,
}

_KOKORO_SPEAKERS: Dict[str, tuple[int, str]] = {
    "af_bella": (2, "en-us"),
    "af_heart": (3, "en-us"),
    "af_nova": (7, "en-us"),
    "am_fenrir": (14, "en-us"),
    "am_michael": (16, "en-us"),
    "am_onyx": (17, "en-us"),
    "bf_emma": (21, "en-GB-x-rp"),
    "bm_daniel": (24, "en-GB-x-rp"),
    "bm_george": (26, "en-GB-x-rp"),
    "bm_lewis": (27, "en-GB-x-rp"),
    "pf_dora": (42, "pt-br"),
    "pm_alex": (43, "pt-br"),
    "pm_santa": (44, "pt-br"),
}


def _default_voice_root() -> Path:
    return Path(
        os.environ.get(
            "WISDAI_VOICE_ASSETS_DIR",
            str(Path.home() / "Library/Application Support/WisdAI/Voice"),
        )
    )


@TTSRegistry.register("sherpa-clean")
class SherpaOnnxCleanTTSBackend(TTSBackend):
    """Low-RAM clean neural TTS backend using WisdAI's native sherpa-onnx C-API."""

    backend_id = "sherpa-clean"

    def __init__(self, voice_root: Optional[Path] = None) -> None:
        self._root = voice_root or _default_voice_root()
        self._lock = threading.Lock()
        self._lib: Any = None
        self._handles: Dict[str, Any] = {}

    def _lib_path(self) -> Optional[Path]:
        candidates = sorted(
            self._root.glob("Runtimes/sherpa-onnx-*/**/libsherpa-onnx-c-api.dylib")
        )
        return candidates[0] if candidates else None

    def _supertonic_dir(self) -> Optional[Path]:
        candidates = sorted(
            self._root.glob("Models/supertonic-*/*supertonic*")
        )
        for cand in candidates:
            if (cand / "vocoder.int8.onnx").is_file():
                return cand
        return None

    def _kokoro_dir(self) -> Optional[Path]:
        candidates = sorted(
            self._root.glob("Models/kokoro-*/*kokoro*")
        )
        for cand in candidates:
            if (cand / "model.int8.onnx").is_file():
                return cand
        return None

    def _ensure_lib(self):
        if self._lib is not None:
            return self._lib
        lib_path = self._lib_path()
        if not lib_path or not lib_path.is_file():
            raise RuntimeError("libsherpa-onnx-c-api.dylib is not installed.")
        lib = ctypes.CDLL(str(lib_path))
        lib.SherpaOnnxCreateOfflineTts.argtypes = [ctypes.POINTER(_TtsCfg)]
        lib.SherpaOnnxCreateOfflineTts.restype = ctypes.c_void_p
        lib.SherpaOnnxDestroyOfflineTts.argtypes = [ctypes.c_void_p]
        lib.SherpaOnnxOfflineTtsSampleRate.argtypes = [ctypes.c_void_p]
        lib.SherpaOnnxOfflineTtsSampleRate.restype = ctypes.c_int32
        lib.SherpaOnnxOfflineTtsGenerateWithConfig.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.POINTER(_GenCfg),
            ctypes.c_void_p,
            ctypes.c_void_p,
        ]
        lib.SherpaOnnxOfflineTtsGenerateWithConfig.restype = ctypes.POINTER(_GeneratedAudio)
        lib.SherpaOnnxDestroyOfflineTtsGeneratedAudio.argtypes = [
            ctypes.POINTER(_GeneratedAudio)
        ]
        self._lib = lib
        return lib

    def _base_cfg(self) -> _TtsCfg:
        cfg = _TtsCfg()
        cfg.model.num_threads = 2
        cfg.model.debug = 0
        cfg.model.provider = b"cpu"
        cfg.max_num_sentences = 1
        cfg.silence_scale = 0.2
        cfg.model.vits.noise_scale = 0.667
        cfg.model.vits.noise_scale_w = 0.8
        cfg.model.vits.length_scale = 1.0
        cfg.model.matcha.noise_scale = 0.667
        cfg.model.matcha.length_scale = 1.0
        cfg.model.kokoro.length_scale = 1.0
        cfg.model.kitten.length_scale = 1.0
        cfg.model.zipvoice.feat_scale = 0.1
        cfg.model.zipvoice.t_shift = 0.5
        cfg.model.zipvoice.target_rms = 0.1
        cfg.model.zipvoice.guidance_scale = 1.0
        return cfg

    def _get_handle(self, key: str) -> tuple[Any, str]:
        with self._lock:
            if key in self._handles:
                return self._handles[key], key
            lib = self._ensure_lib()
            cfg = self._base_cfg()
            if key == "supertonic":
                st = self._supertonic_dir()
                if st is None:
                    raise RuntimeError("Supertonic-3 model directory not installed.")
                cfg.model.supertonic.duration_predictor = str(st / "duration_predictor.int8.onnx").encode()
                cfg.model.supertonic.text_encoder = str(st / "text_encoder.int8.onnx").encode()
                cfg.model.supertonic.vector_estimator = str(st / "vector_estimator.int8.onnx").encode()
                cfg.model.supertonic.vocoder = str(st / "vocoder.int8.onnx").encode()
                cfg.model.supertonic.tts_json = str(st / "tts.json").encode()
                cfg.model.supertonic.unicode_indexer = str(st / "unicode_indexer.bin").encode()
                cfg.model.supertonic.voice_style = str(st / "voice.bin").encode()
            elif key.startswith("kokoro:"):
                lang = key.split(":", 1)[1]
                kd = self._kokoro_dir()
                if kd is None:
                    raise RuntimeError("Kokoro-82M ONNX directory not installed.")
                cfg.model.kokoro.model = str(kd / "model.int8.onnx").encode()
                cfg.model.kokoro.voices = str(kd / "voices.bin").encode()
                cfg.model.kokoro.tokens = str(kd / "tokens.txt").encode()
                cfg.model.kokoro.data_dir = str(kd / "espeak-ng-data").encode()
                cfg.model.kokoro.dict_dir = str(kd / "dict").encode()
                cfg.model.kokoro.lexicon = (
                    f"{kd / 'lexicon-us-en.txt'},{kd / 'lexicon-gb-en.txt'}"
                ).encode()
                cfg.model.kokoro.lang = lang.encode()
            else:
                raise ValueError(f"Unsupported backend key {key}")
            handle = lib.SherpaOnnxCreateOfflineTts(ctypes.byref(cfg))
            if not handle:
                raise RuntimeError(f"SherpaOnnxCreateOfflineTts returned NULL for {key}")
            self._handles[key] = handle
            return handle, key

    def available_voices(self) -> List[str]:
        voices: List[str] = []
        if self._supertonic_dir() is not None:
            voices.extend(sorted(_SUPERTONIC_SPEAKERS.keys()))
        if self._kokoro_dir() is not None:
            voices.extend(sorted(_KOKORO_SPEAKERS.keys()))
        return voices

    def health(self) -> bool:
        return bool(self._lib_path()) and (
            self._supertonic_dir() is not None or self._kokoro_dir() is not None
        )

    def synthesize(
        self,
        text: str,
        *,
        voice_id: str = "supertonic:m4",
        speed: float = 1.0,
        output_format: str = "wav",
        language: str = "pt-BR",
    ) -> TTSResult:
        chosen = (voice_id or "supertonic:m4").strip()
        if chosen in _KOKORO_SPEAKERS:
            sid, klang = _KOKORO_SPEAKERS[chosen]
            handle, _ = self._get_handle(f"kokoro:{klang}")
            payload_text = text.strip()
            num_steps = 0
        else:
            if chosen not in _SUPERTONIC_SPEAKERS:
                chosen = "supertonic:m4"
            sid = _SUPERTONIC_SPEAKERS[chosen]
            handle, _ = self._get_handle("supertonic")
            lang_tag = "en" if language.lower().startswith("en") else "pt"
            clean = _normalize_brand_pronunciation(text, language)
            if not clean.startswith("<"):
                clean = f"<{lang_tag}>{clean}</{lang_tag}>"
            payload_text = clean
            num_steps = 8

        lib = self._ensure_lib()
        with self._lock:
            gcfg = _GenCfg()
            gcfg.silence_scale = 0.2
            gcfg.speed = float(max(0.65, min(1.5, speed)))
            gcfg.sid = sid
            gcfg.num_steps = num_steps
            ptr = lib.SherpaOnnxOfflineTtsGenerateWithConfig(
                handle, payload_text.encode("utf-8"), ctypes.byref(gcfg), None, None
            )
            if not ptr:
                raise RuntimeError("Sherpa-ONNX returned empty audio buffer")
            try:
                n = ptr.contents.n
                sr = ptr.contents.sample_rate or int(
                    lib.SherpaOnnxOfflineTtsSampleRate(handle)
                )
                samples = np.ctypeslib.as_array(ptr.contents.samples, shape=(n,)).copy()
            finally:
                lib.SherpaOnnxDestroyOfflineTtsGeneratedAudio(ptr)

        if samples.size > 0:
            dc = float(np.mean(samples))
            if abs(dc) > 1e-4:
                samples = samples - dc
        pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).astype(np.int16)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sr)
            wf.writeframes(pcm.tobytes())
        dur = len(pcm) / float(sr) if sr else 0.0
        return TTSResult(
            audio=buf.getvalue(),
            format="wav",
            duration_seconds=dur,
            voice_id=chosen,
            sample_rate=sr,
            metadata={"backend": self.backend_id, "sid": sid},
        )

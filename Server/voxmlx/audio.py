import math

import mlx.core as mx
import numpy as np
import soundfile as sf

SAMPLE_RATE = 16000
N_FFT = 400
HOP_LENGTH = 160
N_MELS = 128
GLOBAL_LOG_MEL_MAX = 1.5
SAMPLES_PER_TOKEN = HOP_LENGTH * 2 * 4  # hop * conv_stride * downsample = 1280


def load_audio(path: str) -> np.ndarray:
    audio, sr = sf.read(path, dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != SAMPLE_RATE:
        duration = len(audio) / sr
        n_out = int(duration * SAMPLE_RATE)
        indices = np.linspace(0, len(audio) - 1, n_out)
        idx = indices.astype(np.int64)
        frac = indices - idx
        idx_next = np.minimum(idx + 1, len(audio) - 1)
        audio = audio[idx] * (1 - frac) + audio[idx_next] * frac
        audio = audio.astype(np.float32)
    return audio


def pad_audio(
    audio: np.ndarray,
    n_left_pad_tokens: int = 32,
    n_right_pad_tokens: int = 17,
) -> np.ndarray:
    left_pad = n_left_pad_tokens * SAMPLES_PER_TOKEN
    right_align = (SAMPLES_PER_TOKEN - (len(audio) % SAMPLES_PER_TOKEN)) % SAMPLES_PER_TOKEN
    right_pad = right_align + n_right_pad_tokens * SAMPLES_PER_TOKEN
    return np.pad(audio, (left_pad, right_pad))


def mel_filter_bank(
    sr: int = SAMPLE_RATE,
    n_fft: int = N_FFT,
    n_mels: int = N_MELS,
    f_min: float = 0.0,
    f_max: float = 8000.0,
) -> np.ndarray:
    """Slaney-style mel filter bank (matching mistral_common/audio.py)."""

    def hz_to_mel(f):
        min_log_hz = 1000.0
        min_log_mel = 15.0
        logstep = 27.0 / np.log(6.4)
        mels = 3.0 * f / 200.0
        if isinstance(f, np.ndarray):
            log_region = f >= min_log_hz
            mels[log_region] = min_log_mel + np.log(f[log_region] / min_log_hz) * logstep
        elif f >= min_log_hz:
            mels = min_log_mel + np.log(f / min_log_hz) * logstep
        return mels

    def mel_to_hz(m):
        min_log_hz = 1000.0
        min_log_mel = 15.0
        logstep = np.log(6.4) / 27.0
        freq = 200.0 * m / 3.0
        log_region = m >= min_log_mel
        freq[log_region] = min_log_hz * np.exp(logstep * (m[log_region] - min_log_mel))
        return freq

    n_freqs = n_fft // 2 + 1
    fft_freqs = np.linspace(0, sr / 2, n_freqs)
    mel_min = hz_to_mel(f_min)
    mel_max = hz_to_mel(f_max)
    mel_freqs = np.linspace(mel_min, mel_max, n_mels + 2)
    filter_freqs = mel_to_hz(mel_freqs)
    filter_diff = np.diff(filter_freqs)

    slopes = np.expand_dims(filter_freqs, 0) - np.expand_dims(fft_freqs, 1)
    down_slopes = -slopes[:, :-2] / filter_diff[:-1]
    up_slopes = slopes[:, 2:] / filter_diff[1:]
    fb = np.maximum(np.zeros(1), np.minimum(down_slopes, up_slopes))

    enorm = 2.0 / (filter_freqs[2 : n_mels + 2] - filter_freqs[:n_mels])
    fb *= np.expand_dims(enorm, 0)

    return fb.T.astype(np.float32)  # [n_mels, n_freqs]


_MEL_FILTERS = None
_STFT_WINDOW = None
_DFT_REAL = None
_DFT_IMAG = None


def _get_mel_filters() -> mx.array:
    global _MEL_FILTERS
    if _MEL_FILTERS is None:
        _MEL_FILTERS = mx.array(mel_filter_bank())
    return _MEL_FILTERS


def _get_stft_components() -> tuple[mx.array, mx.array, mx.array]:
    global _STFT_WINDOW, _DFT_REAL, _DFT_IMAG
    if _STFT_WINDOW is None:
        _STFT_WINDOW = mx.array(np.hanning(N_FFT + 1)[:-1].astype(np.float32))
        n_freqs = N_FFT // 2 + 1
        k = mx.arange(n_freqs).astype(mx.float32)[:, None]
        n = mx.arange(N_FFT).astype(mx.float32)[None, :]
        angles = -2.0 * math.pi * (k @ n) / N_FFT
        _DFT_REAL = mx.cos(angles)
        _DFT_IMAG = mx.sin(angles)
    return _STFT_WINDOW, _DFT_REAL, _DFT_IMAG


def log_mel_spectrogram(audio: np.ndarray) -> mx.array:
    audio_mx = mx.array(audio)

    window = mx.array(np.hanning(N_FFT + 1)[:-1].astype(np.float32))
    n_freqs = N_FFT // 2 + 1

    pad_len = N_FFT // 2
    audio_mx = mx.pad(audio_mx, [(pad_len, pad_len)])

    n_frames = 1 + (audio_mx.shape[0] - N_FFT) // HOP_LENGTH
    t = mx.arange(N_FFT)[None, :]
    starts = (mx.arange(n_frames) * HOP_LENGTH)[:, None]
    indices = starts + t
    frames = audio_mx[indices] * window[None, :]

    k = mx.arange(n_freqs).astype(mx.float32)[:, None]
    n = mx.arange(N_FFT).astype(mx.float32)[None, :]
    angles = -2.0 * math.pi * (k @ n) / N_FFT
    dft_real = mx.cos(angles)
    dft_imag = mx.sin(angles)
    spec_real = frames @ dft_real.T
    spec_imag = frames @ dft_imag.T

    magnitudes = spec_real[:-1] ** 2 + spec_imag[:-1] ** 2

    mel_filters = _get_mel_filters()
    mel_spec = magnitudes @ mel_filters.T

    log_spec = mx.log10(mx.maximum(mel_spec, 1e-10))

    log_spec = mx.maximum(log_spec, GLOBAL_LOG_MEL_MAX - 8.0)
    log_spec = (log_spec + 4.0) / 4.0

    return log_spec.T


def log_mel_spectrogram_step(audio_chunk: np.ndarray, audio_tail: np.ndarray | None) -> tuple[mx.array, np.ndarray]:
    """Incremental mel spectrogram for streaming."""
    tail_len = N_FFT - HOP_LENGTH  # 240

    if audio_tail is not None:
        combined = np.concatenate([audio_tail, audio_chunk])
    else:
        pad_len = N_FFT // 2
        combined = np.concatenate([np.zeros(pad_len, dtype=np.float32), audio_chunk])

    new_tail = combined[-tail_len:].copy()

    audio_mx = mx.array(combined)

    window, dft_real, dft_imag = _get_stft_components()

    n_frames = 1 + (audio_mx.shape[0] - N_FFT) // HOP_LENGTH
    if n_frames <= 0:
        return mx.zeros((N_MELS, 0)), new_tail

    t = mx.arange(N_FFT)[None, :]
    starts = (mx.arange(n_frames) * HOP_LENGTH)[:, None]
    indices = starts + t
    frames = audio_mx[indices] * window[None, :]

    spec_real = frames @ dft_real.T
    spec_imag = frames @ dft_imag.T

    magnitudes = spec_real**2 + spec_imag**2

    mel_filters = _get_mel_filters()
    mel_spec = magnitudes @ mel_filters.T

    log_spec = mx.log10(mx.maximum(mel_spec, 1e-10))
    log_spec = mx.maximum(log_spec, GLOBAL_LOG_MEL_MAX - 8.0)
    log_spec = (log_spec + 4.0) / 4.0

    return log_spec.T, new_tail

import math

import mlx.core as mx
import mlx.nn as nn

from .cache import RotatingKVCache
from .encoder import CausalWhisperEncoder
from .language_model import LanguageModel


class TimeEmbedding(nn.Module):
    def __init__(self, dim: int = 32, theta: float = 10000.0):
        super().__init__()
        self.dim = dim
        inv_freq = mx.exp(-math.log(theta) * mx.arange(dim // 2).astype(mx.float32) / (dim // 2))
        self._inv_freq = inv_freq

    def __call__(self, t: mx.array) -> mx.array:
        t = t.reshape(-1, 1).astype(mx.float32)
        emb = t * self._inv_freq
        return mx.concatenate([mx.cos(emb), mx.sin(emb)], axis=-1)


class AudioLanguageAdapter(nn.Module):
    def __init__(self, in_dim: int = 5120, out_dim: int = 3072):
        super().__init__()
        self.w_in = nn.Linear(in_dim, out_dim, bias=False)
        self.w_out = nn.Linear(out_dim, out_dim, bias=False)

    def __call__(self, x: mx.array) -> mx.array:
        return self.w_out(nn.gelu(self.w_in(x)))


class VoxtralRealtime(nn.Module):
    def __init__(self, config: dict):
        super().__init__()
        enc = config["multimodal"]["whisper_model_args"]["encoder_args"]
        audio_enc = enc["audio_encoding_args"]
        downsample = config["multimodal"]["whisper_model_args"]["downsample_args"]["downsample_factor"]

        self.encoder = CausalWhisperEncoder(
            in_channels=audio_enc["num_mel_bins"],
            dim=enc["dim"],
            n_layers=enc["n_layers"],
            n_heads=enc["n_heads"],
            head_dim=enc["head_dim"],
            hidden_dim=enc["hidden_dim"],
            rope_theta=enc["rope_theta"],
            sliding_window=enc["sliding_window"],
        )

        adapter_in = enc["dim"] * downsample
        self.adapter = AudioLanguageAdapter(adapter_in, config["dim"])

        cond_dim = config.get("ada_rms_norm_t_cond_dim", 32)
        self.language_model = LanguageModel(
            dim=config["dim"],
            n_layers=config["n_layers"],
            n_heads=config["n_heads"],
            n_kv_heads=config["n_kv_heads"],
            head_dim=config["head_dim"],
            hidden_dim=config["hidden_dim"],
            vocab_size=config["vocab_size"],
            rope_theta=config["rope_theta"],
            cond_dim=cond_dim,
        )

        self.time_embedding = TimeEmbedding(dim=config["dim"])
        self.downsample_factor = downsample
        self._encoder_dim = enc["dim"]

    def encode(self, mel: mx.array) -> mx.array:
        T = mel.shape[1]
        if T % 2 != 0:
            mel = mel[:, 1:]

        x = self.encoder(mel)
        x = x[0]

        L = x.shape[0]
        remainder = L % self.downsample_factor
        if remainder != 0:
            x = x[remainder:]
            L = x.shape[0]

        x = x.reshape(L // self.downsample_factor, -1)
        x = self.adapter(x)
        return x

    def encode_step(self, new_mel, conv1_tail, conv2_tail, encoder_cache, ds_buf):
        """Incrementally encode new mel frames."""
        x_mel = new_mel.T[None, :, :].astype(self.encoder.conv1.weight.dtype)

        x, conv1_tail, conv2_tail = self.encoder.forward_conv_step(x_mel, conv1_tail, conv2_tail)

        if encoder_cache is None:
            encoder_cache = [RotatingKVCache(8192) for _ in range(len(self.encoder.layers))]

        x = self.encoder.forward_transformer(x, cache=encoder_cache)
        x = x[0]

        if ds_buf is not None:
            x = mx.concatenate([ds_buf, x])
        n_complete = (x.shape[0] // self.downsample_factor) * self.downsample_factor
        if n_complete == 0:
            return None, conv1_tail, conv2_tail, encoder_cache, x

        ds_buf = x[n_complete:] if x.shape[0] > n_complete else None
        x = x[:n_complete]

        x = x.reshape(n_complete // self.downsample_factor, -1)
        x = self.adapter(x)
        return x, conv1_tail, conv2_tail, encoder_cache, ds_buf

    def decode(
        self,
        embeddings: mx.array,
        t_cond: mx.array,
        mask=None,
        cache: list | None = None,
    ):
        return self.language_model(embeddings, t_cond, mask, cache)

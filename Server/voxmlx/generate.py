import mlx.core as mx

from .audio import load_audio, log_mel_spectrogram, pad_audio
from .cache import RotatingKVCache
from .model import VoxtralRealtime


def generate(
    model: VoxtralRealtime,
    audio_path: str,
    prompt_tokens: list[int],
    n_delay_tokens: int,
    temperature: float = 0.0,
    eos_token_id: int = 2,
    sliding_window: int = 8192,
) -> list[int]:
    audio = load_audio(audio_path)
    audio = pad_audio(audio)
    mel = log_mel_spectrogram(audio)

    audio_embeds = model.encode(mel)
    mx.eval(audio_embeds)
    N_audio = audio_embeds.shape[0]

    t_cond = model.time_embedding(mx.array([n_delay_tokens], dtype=mx.float32))

    prefix_len = len(prompt_tokens)
    prompt_ids = mx.array([prompt_tokens])
    text_embeds = model.language_model.embed(prompt_ids)[0]

    prefix_embeds = text_embeds + audio_embeds[:prefix_len]
    prefix_embeds = prefix_embeds[None, :, :]

    n_layers = len(model.language_model.layers)
    cache = [RotatingKVCache(sliding_window) for _ in range(n_layers)]

    def sample(logits):
        if temperature <= 0:
            return mx.argmax(logits[0, -1:], axis=-1).squeeze()
        return mx.random.categorical(logits[0, -1:] / temperature).squeeze()

    def step(token, pos):
        token_embed = model.language_model.embed(token.reshape(1, 1))[0, 0]
        step_embed = (audio_embeds[pos] + token_embed)[None, None, :]
        logits = model.decode(step_embed, t_cond, mask=None, cache=cache)
        return sample(logits)

    logits = model.decode(prefix_embeds, t_cond, "causal", cache)
    mx.eval(logits, *[x for c in cache for x in (c.keys, c.values)])

    y = sample(logits)
    mx.async_eval(y)

    output_tokens = []
    for pos in range(prefix_len, N_audio):
        next_y = step(y, pos)
        mx.async_eval(next_y)

        token_id = y.item()
        if token_id == eos_token_id:
            break
        output_tokens.append(token_id)

        if pos % 256 == 0:
            mx.clear_cache()

        y = next_y

    if output_tokens and output_tokens[-1] == eos_token_id:
        output_tokens = output_tokens[:-1]

    return output_tokens

import unicodedata

import mlx.core as mx
import numpy as np
from mistral_common.tokens.tokenizers.base import SpecialTokenPolicy

_MASK_CACHE = {}
_JAPANESE_RANGES = (
    ("\u3040", "\u30ff"),
    ("\u3400", "\u9fff"),
    ("\uf900", "\ufaff"),
    ("\uff66", "\uff9f"),
)


def normalize_allowed_languages(value):
    if not value:
        return set()
    return {str(item).lower().split("-")[0] for item in value if str(item).strip()}


def make_language_logit_mask(tokenizer, allowed_languages, vocab_size):
    allowed = frozenset(normalize_allowed_languages(allowed_languages))
    if not allowed:
        return None

    cache_key = (id(tokenizer), allowed, vocab_size)
    cached = _MASK_CACHE.get(cache_key)
    if cached is not None:
        return cached

    penalties = np.zeros(vocab_size, dtype=np.float32)
    for token_id in range(vocab_size):
        text = tokenizer.decode([token_id], special_token_policy=SpecialTokenPolicy.IGNORE)
        if _blocks_token(text, allowed):
            penalties[token_id] = -1e9

    mask = mx.array(penalties)
    mx.eval(mask)
    _MASK_CACHE[cache_key] = mask
    return mask


def _blocks_token(text, allowed):
    if not text:
        return False

    if allowed == {"ja"}:
        return any(_is_ascii_letter(char) or (_is_letter(char) and not _is_japanese(char)) for char in text)

    if allowed == {"en"}:
        return any(_is_japanese(char) or (_is_letter(char) and not _is_ascii_letter(char)) for char in text)

    if allowed == {"ja", "en"}:
        return any(_is_letter(char) and not _is_ascii_letter(char) and not _is_japanese(char) for char in text)

    return False


def _is_letter(char):
    return unicodedata.category(char).startswith("L")


def _is_ascii_letter(char):
    return ("a" <= char <= "z") or ("A" <= char <= "Z")


def _is_japanese(char):
    return any(start <= char <= end for start, end in _JAPANESE_RANGES)

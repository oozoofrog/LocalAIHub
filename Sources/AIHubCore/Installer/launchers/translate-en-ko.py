#!/usr/bin/env python3
"""Translate English text to Korean with the installed local Marian model."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path


PARAGRAPH_BREAK = re.compile(r"(\r?\n(?:[ \t]*\r?\n)+)")
MAX_TRANSLATION_TOKENS = 480


def source_limit(tokenizer, model) -> int:
    """Leave room for special tokens and cap each encoder request at 480 tokens."""
    limits = [MAX_TRANSLATION_TOKENS]
    for value in (tokenizer.model_max_length, getattr(model.config, "max_position_embeddings", None)):
        if isinstance(value, int) and 16 < value < 100_000:
            limits.append(value - 8)
    return min(limits)


def source_tokens(tokenizer, text: str) -> int:
    return len(tokenizer.encode(text, add_special_tokens=True, truncation=False))


def chunks_for_paragraph(tokenizer, paragraph: str, limit: int) -> list[str]:
    if source_tokens(tokenizer, paragraph) <= limit:
        return [paragraph]

    chunks: list[str] = []
    current = ""
    sentences = re.split(r"(?<=[.!?])\s+", paragraph.strip())
    for sentence in sentences:
        if not sentence:
            continue
        pieces = [sentence] if source_tokens(tokenizer, sentence) <= limit else sentence.split()
        for piece in pieces:
            if source_tokens(tokenizer, piece) > limit:
                raise ValueError("A single word exceeds the model input limit; shorten the input")
            candidate = f"{current} {piece}" if current else piece
            if source_tokens(tokenizer, candidate) <= limit:
                current = candidate
            else:
                chunks.append(current)
                current = piece
    if current:
        chunks.append(current)
    if not chunks:
        raise ValueError("Could not split a long paragraph without truncation")
    return chunks


def translate_text(text: str, tokenizer, model, torch) -> str:
    limit = source_limit(tokenizer, model)
    eos = model.generation_config.eos_token_id
    if eos is None:
        eos = model.config.eos_token_id
    if eos is None:
        raise RuntimeError("The translation model has no end-of-sequence token")
    eos_ids = set(eos if isinstance(eos, list) else [eos])
    output: list[str] = []

    for paragraph in PARAGRAPH_BREAK.split(text):
        if not paragraph or PARAGRAPH_BREAK.fullmatch(paragraph):
            output.append(paragraph)
            continue

        leading = paragraph[: len(paragraph) - len(paragraph.lstrip())]
        trailing = paragraph[len(paragraph.rstrip()) :]
        body = paragraph.strip()
        if not body:
            output.append(paragraph)
            continue

        translated_chunks: list[str] = []
        for chunk in chunks_for_paragraph(tokenizer, body, limit):
            encoded = tokenizer(chunk, return_tensors="pt", truncation=False)
            if encoded["input_ids"].shape[-1] > limit:
                raise ValueError("Input exceeds the model token limit after splitting")
            with torch.inference_mode():
                generated = model.generate(
                    **encoded, max_new_tokens=MAX_TRANSLATION_TOKENS, num_beams=4
                )
            if generated.shape[-1] >= MAX_TRANSLATION_TOKENS + 1:
                raise RuntimeError("Translation reached the output token limit; split the input further")
            if int(generated[0, -1]) not in eos_ids:
                raise RuntimeError("Translation reached the output token limit; split the input further")
            translated = tokenizer.decode(generated[0], skip_special_tokens=True).strip()
            if not translated:
                raise RuntimeError("The translation model returned an empty chunk")
            translated_chunks.append(translated)
        output.append(leading + " ".join(translated_chunks) + trailing)

    return "".join(output)


def write_new_file(path: Path, contents: str) -> None:
    if path.exists() or path.is_symlink():
        raise FileExistsError(f"output already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=".translate-en-ko-", delete=False
        ) as file:
            temporary = Path(file.name)
            file.write(contents)
        os.link(temporary, path)  # Create only if the destination is still absent.
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--text", help="Literal English text")
    source.add_argument("--input", type=Path, help="UTF-8 English text file")
    parser.add_argument("--output", type=Path, help="Write UTF-8 translation to a new file; default: stdout")
    args = parser.parse_args()

    if args.input is not None:
        text = args.input.expanduser().read_text(encoding="utf-8")
    else:
        text = args.text
    if not text or not text.strip():
        parser.error("English input is empty")

    root = Path(os.environ.get("AIHUB_ROOT", Path(__file__).resolve().parents[1]))
    checkpoint = root / "Models/Translation/opus-mt-tc-big-en-ko"
    if not (checkpoint / "model.safetensors").is_file():
        parser.error(f"local translation model is missing: {checkpoint}")

    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer
    import torch

    tokenizer = AutoTokenizer.from_pretrained(checkpoint, local_files_only=True)
    model = AutoModelForSeq2SeqLM.from_pretrained(
        checkpoint, local_files_only=True, use_safetensors=True
    ).to("cpu").float().eval()
    translation = translate_text(text, tokenizer, model, torch)

    if args.output is None:
        sys.stdout.write(translation)
    else:
        output = args.output.expanduser().absolute()
        write_new_file(output, translation)
        print(f"Saved {output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, UnicodeError, RuntimeError, ValueError) as error:
        print(f"Translation failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error

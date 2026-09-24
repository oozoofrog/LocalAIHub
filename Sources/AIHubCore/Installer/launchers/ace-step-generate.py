#!/usr/bin/env python3
"""Generate one ACE-Step song directly, without starting the Gradio server."""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import sys
import tempfile
from datetime import datetime
from pathlib import Path


def stop_on_sigterm(signum: int, _frame: object) -> None:
    # Unwind the TemporaryDirectory context before exiting; repeated Stop clicks
    # must not interrupt that cleanup.
    signal.signal(signum, signal.SIG_IGN)
    raise SystemExit(128 + signum)


def main() -> int:
    root = Path(os.environ.get("AIHUB_ROOT", Path(__file__).resolve().parents[1]))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", required=True, help="Music description")
    parser.add_argument("--lyrics", default="", help="Literal lyrics, if supplied")
    parser.add_argument("--duration", type=float, default=30.0, help="Target duration in seconds (10-600)")
    parser.add_argument("--seed", type=int, default=-1, help="Nonnegative fixed seed; -1 is random")
    parser.add_argument("--language", default="unknown", help="Vocal language code, such as ko or en")
    parser.add_argument("--bpm", type=int, help="Tempo in beats per minute (30-300)")
    parser.add_argument("--output", type=Path, help="Output WAV, FLAC, or MP3 path")
    args = parser.parse_args()

    prompt = args.prompt.strip()
    if not prompt or len(prompt) >= 512:
        parser.error("--prompt must contain 1-511 characters")
    if len(args.lyrics) >= 4096:
        parser.error("--lyrics must contain fewer than 4096 characters")
    if not 10 <= args.duration <= 600:
        parser.error("--duration must be between 10 and 600 seconds")
    if args.seed < -1:
        parser.error("--seed must be -1 or nonnegative")
    if args.bpm is not None and not 30 <= args.bpm <= 300:
        parser.error("--bpm must be between 30 and 300")

    output = args.output or root / "Output/Audio" / f"ace-step-{datetime.now():%Y%m%d-%H%M%S}.wav"
    output = output.expanduser().absolute()
    audio_format = output.suffix.lower().removeprefix(".")
    if audio_format not in {"wav", "flac", "mp3"}:
        parser.error("--output must end in .wav, .flac, or .mp3")
    if audio_format == "mp3" and shutil.which("ffmpeg") is None:
        parser.error("MP3 output requires ffmpeg on PATH; use WAV/FLAC or install ffmpeg")
    if output.exists() or output.is_symlink():
        parser.error(f"output already exists: {output}")

    checkpoint_dir = root / "Models/ACE-Step-1.5"
    for model_name in ("acestep-v15-turbo", "acestep-5Hz-lm-1.7B"):
        if not (checkpoint_dir / model_name).is_dir():
            parser.error(f"model is not installed: {checkpoint_dir / model_name}")

    from acestep.constants import TASK_INSTRUCTIONS, VALID_LANGUAGES
    from acestep.handler import AceStepHandler
    from acestep.inference import GenerationConfig, GenerationParams, generate_music
    from acestep.llm_inference import LLMHandler

    if args.language not in VALID_LANGUAGES:
        parser.error(f"unsupported vocal language: {args.language}")

    source_dir = root / "Source/ACE-Step-1.5"
    dit_handler = AceStepHandler()
    print("Loading ACE-Step DiT model...", flush=True)
    status, success = dit_handler.initialize_service(
        project_root=str(source_dir),
        config_path="acestep-v15-turbo",
        device="auto",
        offload_to_cpu=False,
    )
    if not success:
        raise RuntimeError(f"DiT initialization failed: {status}")

    llm_handler = LLMHandler()
    print("Loading ACE-Step 1.7B language model...", flush=True)
    status, success = llm_handler.initialize(
        checkpoint_dir=str(checkpoint_dir),
        lm_model_path="acestep-5Hz-lm-1.7B",
        backend="mlx",
        device="auto",
        offload_to_cpu=False,
        dtype=None,
    )
    if not success:
        raise RuntimeError(f"Language model initialization failed: {status}")

    params = GenerationParams(
        task_type="text2music",
        instruction=TASK_INSTRUCTIONS["text2music"],
        thinking=True,
        caption=prompt,
        lyrics=args.lyrics,
        vocal_language=args.language,
        duration=args.duration,
        bpm=args.bpm,
        inference_steps=8,
        guidance_scale=1.0,
        seed=args.seed,
        use_cot_language=args.language == "unknown",
    )
    config = GenerationConfig(
        batch_size=1,
        use_random_seed=args.seed == -1,
        audio_format=audio_format,
    )

    def progress(value: float, desc: str | None = None) -> None:
        if desc:
            print(f"[{value:.0%}] {desc}", file=sys.stderr, flush=True)

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".ace-step-", dir=output.parent) as temp_dir:
        result = generate_music(
            dit_handler,
            llm_handler,
            params=params,
            config=config,
            save_dir=temp_dir,
            progress=progress,
        )
        if not result.success:
            raise RuntimeError(result.error or result.status_message or "Music generation failed")
        if len(result.audios) != 1:
            raise RuntimeError(f"Expected one audio result, got {len(result.audios)}")
        generated_path = Path(result.audios[0].get("path") or "")
        if not generated_path.is_file() or generated_path.stat().st_size == 0:
            raise RuntimeError("Music generation returned no saved audio file")
        os.link(generated_path, output)  # Fails if another process created the destination.

    print(f"Saved {output}", flush=True)
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop_on_sigterm)
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"ACE-Step generation failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error

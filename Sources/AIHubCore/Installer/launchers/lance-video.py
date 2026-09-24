#!/usr/bin/env python3
"""Run Lance text-to-video using the selected Local AI Studio data root."""

from __future__ import annotations

import argparse
import os
from datetime import datetime
from pathlib import Path


AI_ROOT = Path(os.environ.get("AIHUB_ROOT", Path(__file__).resolve().parents[1]))
WEIGHTS = AI_ROOT / "Models/Lance-3B-Video-bf16"
OUTPUTS = AI_ROOT / "Output/Video"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", required=True, help="Text prompt for the video")
    parser.add_argument("--resolution", type=int, default=512)
    parser.add_argument("--frames", type=int, default=17)
    parser.add_argument("--steps", type=int, default=30)
    parser.add_argument("--cfg", type=float, default=4.0)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--memory-mode", choices=("parallel", "auto", "relay"), default="parallel")
    parser.add_argument("--output", type=Path, help="MP4 path; defaults to Output/Video")
    args = parser.parse_args()

    output_path = args.output or OUTPUTS / f"lance-video-{datetime.now():%Y%m%d-%H%M%S}.mp4"
    if output_path.exists():
        parser.error(f"output already exists: {output_path}")

    from lance_mlx.pipeline.t2v import TextToVideoPipeline

    print(f"Loading Lance with memory_mode={args.memory_mode}", flush=True)
    pipeline = TextToVideoPipeline.from_pretrained(
        lance_weights_dir=WEIGHTS,
        vae_safetensors=WEIGHTS / "vae.safetensors",
        memory_mode=args.memory_mode,
    )
    print(f"Loaded Lance with memory_mode={pipeline.memory_mode}", flush=True)
    print(f"Generating {args.frames} frames at {args.resolution}x{args.resolution}, {args.steps} steps", flush=True)
    frames = pipeline.generate(
        args.prompt,
        num_frames=args.frames,
        height=args.resolution,
        width=args.resolution,
        num_steps=args.steps,
        cfg_scale=args.cfg,
        seed=args.seed,
    )

    import imageio

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with imageio.get_writer(output_path, fps=args.fps, codec="libx264") as writer:
        for index, frame in enumerate(frames, start=1):
            writer.append_data(frame)
            print(f"Writing video frame {index}", flush=True)
    print(f"Saved {output_path}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

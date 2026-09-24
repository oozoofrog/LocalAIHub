# Third-party model and runtime notices

Local AI Studio downloads third-party model files and runtime sources into the user-selected storage folder. These materials are not included in this repository. Each upstream project controls its own license and terms; the list below identifies the current sources, while exact revisions and file selections are maintained in `Sources/AIHubCore/Installer/install.sh`.

## Model repositories

- Qwen Image 2.1 GGUF: [leejet/Qwen-Image-2.1-GGUF](https://huggingface.co/leejet/Qwen-Image-2.1-GGUF), derived from [Qwen/Qwen-Image-2.1](https://huggingface.co/Qwen/Qwen-Image-2.1). The Qwen Research License permits non-commercial research or evaluation use; the app requires explicit acceptance before downloading this group.
- Qwen3-VL text encoder: [Qwen/Qwen3-VL-8B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-8B-Instruct-GGUF).
- Qwen3-TTS and Qwen3-ASR MLX checkpoints: [mlx-community](https://huggingface.co/mlx-community).
- Lance-3B Video: [mlx-community/Lance-3B-Video-bf16](https://huggingface.co/mlx-community/Lance-3B-Video-bf16).
- ACE-Step 1.5: [ACE-Step/Ace-Step1.5](https://huggingface.co/ACE-Step/Ace-Step1.5).

Read the license attached to each model repository before use. Do not assume that the Local AI Studio source-code terms grant rights to downloaded model files.

## Runtime sources

- [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)
- [lance-mlx](https://github.com/xocialize/lance-mlx)
- [ACE-Step 1.5](https://github.com/ACE-Step/ACE-Step-1.5)
- [MLX-Audio](https://github.com/Blaizzy/mlx-audio)
- [uv](https://github.com/astral-sh/uv)
- [Hugging Face Hub](https://github.com/huggingface/huggingface_hub)

The installer checks out runtime repositories at fixed commits and installs the listed Python tools into the selected storage folder. Consult each source project and package for its license and notices.

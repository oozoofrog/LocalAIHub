# Local AI Studio

Local AI Studio is a native macOS app and command-line interface for installing and running local image, speech, video, and music models on Apple Silicon. The app downloads the selected model files and their pinned runtime sources into a separate storage folder. Model weights, caches, generated media, and downloaded runtime checkouts are excluded from this Git repository.

## Requirements

- Apple Silicon Mac running macOS 14 or later
- Xcode Command Line Tools
- CMake for the Qwen Image group
- Network access during setup
- Free disk space for the selected model groups and their runtime environments

Approximate model download sizes are shown before setup starts: image 13 GB, speech 12 GB, video 16 GB, and music 10 GB. Runtime packages and caches require additional space. The installer prepares Python 3.12 and Hugging Face's download tool automatically. Keep only one large generator active at a time on a 24 GB Mac.

## Build and open the app

```sh
git clone https://github.com/oozoofrog/LocalAIHub.git
cd LocalAIHub
./script/build_and_run.sh
```

The script builds a self-contained `dist/LocalAIStudio.app` bundle with the installer resources and matching `ai` command, then opens the app. Use `./script/build_and_run.sh build-only` to package the app without opening another instance. When Model Setup runs, it places `ai` in the chosen storage folder alongside the launchers.

On first launch, open **Model Setup**, choose a storage folder, select the model groups, and start the download. The default storage folder is `/Volumes/eyedisk/AI` when that volume is present; otherwise it is `~/AI/LocalAIStudio`. The app remembers a folder selected in Model Setup. Setup shows per-group readiness, the selected download estimate, available volume space, current download percentage when available, elapsed time, and installer activity. Completed groups are detected and skipped on later setup runs.

Qwen Image 2.1 requires accepting its Qwen Research License in the app before its weights are downloaded. The license limits use to non-commercial research or evaluation. [Read the Qwen license](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE).

## Command line

After a model group is installed, the app places the `ai` command in the selected storage folder's `bin` directory:

```sh
AI_ROOT="$HOME/AI/LocalAIStudio" # replace with the folder selected in Model Setup
"$AI_ROOT/bin/ai" status
"$AI_ROOT/bin/ai" models
export PATH="$AI_ROOT/bin:$PATH"

ai image --prompt "A handmade ceramic teapot in soft morning light" --width 512 --height 512
ai image-edit --image /path/to/reference.png --prompt "Change the background to a sunset beach"
ai tts --text "안녕하세요. 음성 합성 환경을 준비했습니다." --model custom-voice --voice Vivian --language Korean
ai transcribe --audio /path/to/recording.wav --model 1.7b --language Korean --format srt
ai video --prompt "A red panda surfing on a sunny wave" --resolution 512 --frames 17 --steps 30 --memory-mode parallel
ai music
```

`ai --help` lists all supported options. TTS supports `custom-voice`, `voice-design` (with `--instruction`), and `clone` (with `--reference-audio` and its exact `--reference-text`). Transcription supports `txt`, `srt`, `vtt`, and `json`. ACE-Step runs in the foreground and serves its local interface at `127.0.0.1:7860`; Ctrl-C stops it. TTS and transcription use unique timestamped output names by default.

## Model and runtime sources

The installer fetches models directly from their publishers or named community repositories at revisions pinned in `Sources/AIHubCore/Installer/install.sh`. Runtime sources are checked out at pinned commits. The app repository does not mirror model weights. Each model, runtime, and Python package has its own terms; review the applicable upstream card and license before using it. See [third-party notices](THIRD_PARTY_NOTICES.md).

The app's readiness checks confirm required local files and launchers are present. A successful download and build do not establish that a model generated a useful result; inference should be checked in the relevant workflow.

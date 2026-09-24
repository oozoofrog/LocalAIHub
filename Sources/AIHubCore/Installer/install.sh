#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_DIR="$SCRIPT_DIR/launchers"
INSTALL_ARGS=("$@")

ROOT="${AIHUB_ROOT:-}"
MODELS=""
ACCEPT_QWEN_LICENSE="false"
DRY_RUN="false"

if [[ -z "$ROOT" ]]; then
  if [[ -d /Volumes/eyedisk/AI ]]; then
    ROOT=/Volumes/eyedisk/AI
  else
    ROOT="$HOME/AI/LocalAIStudio"
  fi
fi

while (($#)); do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || { echo "--root requires a path" >&2; exit 2; }
      ROOT="$2"
      shift 2
      ;;
    --models)
      [[ $# -ge 2 ]] || { echo "--models requires image,audio,video,music,translation or all" >&2; exit 2; }
      MODELS="$2"
      shift 2
      ;;
    --accept-qwen-research-license)
      ACCEPT_QWEN_LICENSE="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    --help|-h)
      cat <<'HELP'
Local AI Studio installer

Usage:
  install.sh --models image,audio,video,music,translation [--root PATH]
             [--accept-qwen-research-license] [--dry-run]

Model groups:
  image  Qwen Image 2.1 generation and editing (about 13 GB)
  audio  Qwen3-TTS and Qwen3-ASR (about 12 GB)
  video  Lance-3B Video (about 16 GB)
  music  ACE-Step 1.5 (about 10 GB)
  translation  OPUS-MT English to Korean (about 2 GB including runtime)

Downloads are placed below ROOT/Models. Model weights are never copied into
the LocalAIHub project or its Git repository.
HELP
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

[[ -n "$MODELS" ]] || { echo "Choose model groups with --models." >&2; exit 2; }
case "$ROOT" in
  '~'*) ROOT="$HOME${ROOT#\~}" ;;
esac
if [[ "$ROOT" != /* ]]; then ROOT="$PWD/$ROOT"; fi
ROOT="${ROOT%/}"

if [[ "$MODELS" == "all" ]]; then
  SELECTED=(image audio video music translation)
else
  IFS=',' read -r -a SELECTED <<< "$MODELS"
fi

SEEN_LIST=""
for item in "${SELECTED[@]}"; do
  case "$item" in image|audio|video|music|translation) ;; *) echo "Unknown model group: $item" >&2; exit 2 ;; esac
  case ",$SEEN_LIST," in *,"$item",*) echo "Duplicate model group: $item" >&2; exit 2 ;; esac
  SEEN_LIST+="$item,"
done

has_selected() {
  local candidate="$1"
  for item in "${SELECTED[@]}"; do
    [[ "$item" == "$candidate" ]] && return 0
  done
  return 1
}

if has_selected image && [[ "$ACCEPT_QWEN_LICENSE" != "true" ]]; then
  echo "Qwen Image 2.1 requires explicit acceptance of its non-commercial research license." >&2
  exit 3
fi

emit_stage() { printf '@@stage\t%s\n' "$1"; }
emit_package() { printf '@@package\t%s\t%s\t%s\n' "$1" "$2" "$3"; }
say() { printf '%s\n' "$1"; }

ROOT_DISPLAY="$ROOT"
if [[ "$DRY_RUN" == "true" ]]; then
  say "Destination: $ROOT_DISPLAY"
  say "Selected: ${SELECTED[*]}"
  for item in "${SELECTED[@]}"; do
    case "$item" in
      image) say "Plan: build stable-diffusion.cpp with Metal; download Qwen Image 2.1 GGUF, text encoder, projector, VAE, and license." ;;
      audio) say "Plan: prepare the MLX-Audio runtime; download three Qwen3-TTS and two Qwen3-ASR snapshots." ;;
      video) say "Plan: prepare lance-mlx; download the 15.6 GB Lance-3B Video BF16 checkpoint." ;;
      music) say "Plan: prepare ACE-Step 1.5; download its main checkpoint and 1.7B LM." ;;
      translation) say "Plan: prepare a Python translation runtime; download the 0.2B English-to-Korean OPUS-MT checkpoint." ;;
    esac
  done
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "This installer currently supports Apple Silicon macOS only." >&2
  exit 2
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Install Xcode Command Line Tools before setting up Local AI Studio." >&2
  exit 2
fi
for command_name in git curl; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Install $command_name before setting up Local AI Studio." >&2
    exit 2
  fi
done
if has_selected image && ! command -v cmake >/dev/null 2>&1; then
  echo "Install CMake (for example, with 'brew install cmake') before setting up Qwen Image." >&2
  exit 2
fi

# Keep the installer in a separate job so a Stop signal can reach the active
# download/build process, not only the shell that is waiting for it.
if [[ "${AIHUB_INSTALL_SUPERVISED:-}" != "1" ]]; then
  worker_pid=""
  worker_pgid=""

  terminate_descendants() {
    local parent="$1" child
    while IFS= read -r child; do
      [[ -n "$child" ]] || continue
      terminate_descendants "$child"
      builtin kill -TERM "$child" 2>/dev/null || true
    done < <(pgrep -P "$parent" 2>/dev/null || true)
  }

  stop_supervised_install() {
    trap - TERM INT
    if [[ -n "$worker_pid" ]] && builtin kill -0 "$worker_pid" 2>/dev/null; then
      local current_pgid
      current_pgid="$(ps -o pgid= -p "$worker_pid" 2>/dev/null | tr -d '[:space:]' || true)"
      if [[ -n "$worker_pgid" && "$worker_pgid" == "$worker_pid" && "$current_pgid" == "$worker_pgid" ]]; then
        builtin kill -TERM -- "-$worker_pgid" 2>/dev/null || true
      else
        terminate_descendants "$worker_pid"
        builtin kill -TERM "$worker_pid" 2>/dev/null || true
      fi
      wait "$worker_pid" 2>/dev/null || true
    fi
    exit 143
  }

  trap stop_supervised_install TERM INT
  if set -m 2>/dev/null; then :; fi
  AIHUB_INSTALL_SUPERVISED=1 /bin/bash "$0" "${INSTALL_ARGS[@]}" &
  worker_pid=$!
  set +m
  worker_pgid="$(ps -o pgid= -p "$worker_pid" 2>/dev/null | tr -d '[:space:]' || true)"
  if wait "$worker_pid"; then
    exit 0
  else
    exit $?
  fi
fi

mkdir -p "$ROOT" "$ROOT/bin" "$ROOT/Models" "$ROOT/Source" "$ROOT/Environments" "$ROOT/Cache"
export AIHUB_ROOT="$ROOT"
export UV_CACHE_DIR="$ROOT/Cache/uv"
export UV_PYTHON_INSTALL_DIR="$ROOT/Cache/python"
export HF_HOME="$ROOT/Cache/huggingface"
export HF_HUB_CACHE="$HF_HOME/hub"
export HF_XET_CACHE="$HF_HOME/xet"
export HF_ASSETS_CACHE="$HF_HOME/assets"
export XDG_CACHE_HOME="$ROOT/Cache/xdg"
mkdir -p "$UV_CACHE_DIR" "$UV_PYTHON_INSTALL_DIR" "$HF_HOME" "$XDG_CACHE_HOME"

if command -v uv >/dev/null 2>&1; then
  UV="$(command -v uv)"
elif [[ -x "$ROOT/bin/uv" ]]; then
  UV="$ROOT/bin/uv"
else
  emit_stage "Installing the uv runtime manager"
  curl --fail --location --silent --show-error https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR="$ROOT/bin" UV_NO_MODIFY_PATH=1 sh
  UV="$ROOT/bin/uv"
fi

if ! "$UV" python list --only-installed 2>/dev/null | grep -q '3\.12'; then
  emit_stage "Preparing Python 3.12"
  "$UV" python install 3.12
fi

if [[ ! -x "$ROOT/bin/hf" ]]; then
  emit_stage "Preparing the Hugging Face download tool"
  UV_TOOL_BIN_DIR="$ROOT/bin" UV_TOOL_DIR="$ROOT/Tools/uv" \
    "$UV" tool install --python 3.12 'huggingface_hub[hf_xet]'
fi
HF="$ROOT/bin/hf"
if [[ ! -x "$HF" ]]; then
  echo "Hugging Face CLI was not installed at $HF." >&2
  exit 1
fi

ensure_checkout() {
  local name="$1" url="$2" revision="$3" destination="$4"
  if [[ -d "$destination/.git" ]]; then
    local current dirty
    current="$(git -C "$destination" rev-parse HEAD 2>/dev/null || true)"
    dirty="$(git -C "$destination" status --porcelain --untracked-files=all)"
    if [[ -n "$dirty" ]]; then
      echo "$name source has local changes; preserving it and stopping: $destination" >&2
      return 1
    fi
    if [[ "$current" != "$revision" ]]; then
      emit_stage "Checking out pinned $name source"
      git -C "$destination" fetch --depth 1 origin "$revision"
      git -C "$destination" checkout --detach FETCH_HEAD
    fi
  elif [[ -e "$destination" ]]; then
    echo "$name source path exists but is not a Git checkout: $destination" >&2
    return 1
  else
    emit_stage "Downloading $name source"
    mkdir -p "$(dirname "$destination")"
    git init --quiet "$destination"
    git -C "$destination" remote add origin "$url"
    git -C "$destination" fetch --depth 1 origin "$revision"
    git -C "$destination" checkout --quiet --detach FETCH_HEAD
  fi
  if [[ "$name" == "stable-diffusion.cpp" ]]; then
    git -C "$destination" submodule update --init --recursive --depth 1
  fi
}

download_repo() {
  local package="$1" repo="$2" revision="$3" destination="$4"
  shift 4
  mkdir -p "$destination"
  emit_package "$package" downloading "Downloading $repo"
  "$HF" download "$repo" "$@" --revision "$revision" --local-dir "$destination"
  emit_package "$package" downloading "Verified $repo"
}

group_ready() {
  case "$1" in
    image)
      [[ -x "$ROOT/bin/qwen-image-2.1-generate" && -x "$ROOT/bin/qwen-image-2.1-edit" \
        && -x "$ROOT/Source/stable-diffusion.cpp/build/bin/sd-cli" \
        && -s "$ROOT/Models/Qwen-Image-2.1/diffusion/qwen_image_2.1-Q6_K.gguf" \
        && -s "$ROOT/Models/Qwen-Image-2.1/text_encoder/Qwen3VL-8B-Instruct-Q4_K_M.gguf" \
        && -s "$ROOT/Models/Qwen-Image-2.1/text_encoder/mmproj-Qwen3VL-8B-Instruct-F16.gguf" \
        && -s "$ROOT/Models/Qwen-Image-2.1/vae/qwen_image_2.1_vae_bf16.safetensors" \
        && -s "$ROOT/Models/Qwen-Image-2.1/LICENSE-Qwen-Image-2.1.txt" ]]
      ;;
    audio)
      [[ -x "$ROOT/bin/qwen3-tts" && -x "$ROOT/bin/qwen3-asr" \
        && -x "$ROOT/Environments/mlx-audio-py312/bin/mlx_audio.tts.generate" \
        && -x "$ROOT/Environments/mlx-audio-py312/bin/mlx_audio.stt.generate" \
        && -s "$ROOT/Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit/model.safetensors" \
        && -s "$ROOT/Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit/model.safetensors" \
        && -s "$ROOT/Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-Base-8bit/model.safetensors" \
        && -s "$ROOT/Models/MLX-Audio/Qwen3-ASR-0.6B-8bit/model.safetensors" \
        && -s "$ROOT/Models/MLX-Audio/Qwen3-ASR-1.7B-8bit/model.safetensors" ]]
      ;;
    video)
      [[ -x "$ROOT/bin/lance-video" && -x "$ROOT/Source/lance-mlx/.venv/bin/python" \
        && -s "$ROOT/Models/Lance-3B-Video-bf16/model.safetensors" \
        && -s "$ROOT/Models/Lance-3B-Video-bf16/vae.safetensors" \
        && -s "$ROOT/Models/Lance-3B-Video-bf16/vit.safetensors" ]]
      ;;
    music)
      [[ -x "$ROOT/bin/ace-step" && -x "$ROOT/bin/ace-step-generate" \
        && -s "$ROOT/bin/ace-step-generate.py" && -x "$ROOT/Environments/ACE-Step-1.5-py312/bin/python" \
        && -x "$ROOT/Source/ACE-Step-1.5/start_gradio_ui_macos.sh" \
        && -s "$ROOT/Models/ACE-Step-1.5/acestep-v15-turbo/model.safetensors" \
        && -s "$ROOT/Models/ACE-Step-1.5/acestep-5Hz-lm-1.7B/model.safetensors" ]]
      ;;
    translation)
      local model="$ROOT/Models/Translation/opus-mt-tc-big-en-ko"
      [[ -x "$ROOT/bin/translate-en-ko" && -s "$ROOT/bin/translate-en-ko.py" \
        && -x "$ROOT/Environments/translation-py312/bin/python" \
        && -s "$model/model.safetensors" && -s "$model/config.json" \
        && -s "$model/generation_config.json" && -s "$model/source.spm" \
        && -s "$model/target.spm" && -s "$model/vocab.json" \
        && -s "$model/tokenizer_config.json" && -s "$model/special_tokens_map.json" ]]
      ;;
  esac
}

install_launchers() {
  emit_stage "Installing Local AI Studio launchers"
  for item in "${SELECTED[@]}"; do
    case "$item" in
      image)
        cp "$LAUNCHER_DIR/qwen-image-2.1-generate" "$LAUNCHER_DIR/qwen-image-2.1-edit" "$ROOT/bin/"
        chmod +x "$ROOT/bin/qwen-image-2.1-generate" "$ROOT/bin/qwen-image-2.1-edit"
        mkdir -p "$ROOT/Output/Qwen-Image-2.1"
        ;;
      audio)
        cp "$LAUNCHER_DIR/qwen3-tts" "$LAUNCHER_DIR/qwen3-asr" "$ROOT/bin/"
        chmod +x "$ROOT/bin/qwen3-tts" "$ROOT/bin/qwen3-asr"
        mkdir -p "$ROOT/Output/Audio"
        ;;
      video)
        cp "$LAUNCHER_DIR/lance-video" "$LAUNCHER_DIR/lance-video.py" "$ROOT/bin/"
        chmod +x "$ROOT/bin/lance-video"
        mkdir -p "$ROOT/Output/Video"
        ;;
      music)
        cp "$LAUNCHER_DIR/ace-step" "$LAUNCHER_DIR/ace-step-download" \
          "$LAUNCHER_DIR/ace-step-generate" "$LAUNCHER_DIR/ace-step-generate.py" "$ROOT/bin/"
        chmod +x "$ROOT/bin/ace-step" "$ROOT/bin/ace-step-download" "$ROOT/bin/ace-step-generate"
        mkdir -p "$ROOT/Output/Music"
        ;;
      translation)
        cp "$LAUNCHER_DIR/translate-en-ko" "$LAUNCHER_DIR/translate-en-ko.py" "$ROOT/bin/"
        chmod +x "$ROOT/bin/translate-en-ko"
        mkdir -p "$ROOT/Output/Translation"
        ;;
    esac
  done
}

install_image() {
  emit_package image installing "Preparing the Metal image runtime"
  local sd="$ROOT/Source/stable-diffusion.cpp"
  ensure_checkout stable-diffusion.cpp https://github.com/leejet/stable-diffusion.cpp.git \
    2dc7f5408a632faa03f4222eeafe70908b0212b1 "$sd"
  if [[ ! -x "$sd/build/bin/sd-cli" ]]; then
    emit_stage "Building stable-diffusion.cpp with Metal"
    cmake -S "$sd" -B "$sd/build" -DSD_METAL=ON -DSD_BUILD_EXAMPLES=ON -DCMAKE_BUILD_TYPE=Release
    cmake --build "$sd/build" --config Release --target sd-cli --parallel "$(sysctl -n hw.ncpu)"
  fi
  download_repo image leejet/Qwen-Image-2.1-GGUF cc11433936a06e9765f7c0c0b1f0436cfd2b9856 \
    "$ROOT/Models/Qwen-Image-2.1/diffusion" qwen_image_2.1-Q6_K.gguf
  download_repo image Qwen/Qwen3-VL-8B-Instruct-GGUF f982a07559d4a2f6c8744d840bf6fccab30eea96 \
    "$ROOT/Models/Qwen-Image-2.1/text_encoder" Qwen3VL-8B-Instruct-Q4_K_M.gguf mmproj-Qwen3VL-8B-Instruct-F16.gguf
  download_repo image Comfy-Org/Qwen-Image-2.1 9a44dbdb47cefd046be9c0a13476192f34c8db8e \
    "$ROOT/Models/Qwen-Image-2.1" vae/qwen_image_2.1_vae_bf16.safetensors
  mkdir -p "$ROOT/Models/Qwen-Image-2.1"
  "$HF" download Qwen/Qwen-Image-2.1 LICENSE --revision 790c92633540aa0cb11d9abf19eb46d861714758 \
    --local-dir "$ROOT/Models/Qwen-Image-2.1/license-source"
  cp "$ROOT/Models/Qwen-Image-2.1/license-source/LICENSE" "$ROOT/Models/Qwen-Image-2.1/LICENSE-Qwen-Image-2.1.txt"
  rm -rf "$ROOT/Models/Qwen-Image-2.1/license-source"
}

install_audio() {
  emit_package audio installing "Preparing the MLX-Audio runtime"
  local environment="$ROOT/Environments/mlx-audio-py312"
  if [[ ! -x "$environment/bin/mlx_audio.tts.generate" || ! -x "$environment/bin/mlx_audio.stt.generate" ]]; then
    emit_stage "Installing MLX-Audio for Python 3.12"
    "$UV" venv --python 3.12 "$environment"
    "$UV" pip install --python "$environment/bin/python" 'mlx-audio==0.5.5' 'huggingface_hub[hf_xet]'
  fi
  download_repo audio mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit 41d3337e8b7f2843a75841595fc14e4b9a7a4b96 \
    "$ROOT/Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
  download_repo audio mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit f90d617701d9f7f4ca499291e0b57f2b3c2fd2ee \
    "$ROOT/Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit"
  download_repo audio mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit e7dd0585652209fa0d7783659aad4e8a324de11c \
    "$ROOT/Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-Base-8bit"
  download_repo audio mlx-community/Qwen3-ASR-0.6B-8bit 89e96d92ba34aca20b3e29fb10cc284097d1219f \
    "$ROOT/Models/MLX-Audio/Qwen3-ASR-0.6B-8bit"
  download_repo audio mlx-community/Qwen3-ASR-1.7B-8bit a8379a2e2f9e313c9292cdf1af4055ab56d50d55 \
    "$ROOT/Models/MLX-Audio/Qwen3-ASR-1.7B-8bit"
}

install_video() {
  emit_package video installing "Preparing the Lance MLX runtime"
  local source="$ROOT/Source/lance-mlx"
  ensure_checkout lance-mlx https://github.com/xocialize/lance-mlx.git \
    f8ecc5a86d28b94bd8dc688c200c3e22ffafff4a "$source"
  local environment="$source/.venv"
  if [[ ! -x "$environment/bin/python" ]]; then
    emit_stage "Installing the Lance Python environment"
    UV_PROJECT_ENVIRONMENT="$environment" "$UV" sync --project "$source" --python 3.12 --no-dev
  fi
  download_repo video mlx-community/Lance-3B-Video-bf16 b70ba0a53c14eef573570fe65b31e295bd8216af \
    "$ROOT/Models/Lance-3B-Video-bf16"
}

install_music() {
  emit_package music installing "Preparing ACE-Step 1.5"
  local source="$ROOT/Source/ACE-Step-1.5"
  ensure_checkout ACE-Step-1.5 https://github.com/ACE-Step/ACE-Step-1.5.git \
    ca1e85fe9430179831e6bc6be790c332190a3866 "$source"
  local environment="$ROOT/Environments/ACE-Step-1.5-py312"
  if [[ ! -x "$environment/bin/python" ]]; then
    emit_stage "Installing the ACE-Step Python environment"
    UV_PROJECT_ENVIRONMENT="$environment" "$UV" sync --project "$source" --python 3.12 --no-dev
  fi
  download_repo music ACE-Step/Ace-Step1.5 19671f406d603126926c1b7e2adc169acbcade22 \
    "$ROOT/Models/ACE-Step-1.5"
}

install_translation() {
  emit_package translation installing "Preparing the English-to-Korean runtime"
  local environment="$ROOT/Environments/translation-py312"
  if [[ ! -x "$environment/bin/python" ]]; then
    emit_stage "Creating the translation Python environment"
    "$UV" venv --python 3.12 "$environment"
  fi
  if ! "$environment/bin/python" -c 'import transformers, torch, sentencepiece, sacremoses, safetensors' >/dev/null 2>&1; then
    emit_stage "Installing the translation runtime"
    "$UV" pip install --python "$environment/bin/python" \
      'transformers==4.57.6' 'torch==2.10.0' 'sentencepiece==0.2.2' \
      'sacremoses==0.2.0' 'safetensors==0.7.0'
  fi
  download_repo translation Helsinki-NLP/opus-mt-tc-big-en-ko ae8606b7b29a495f31ce679cee2007f536a3a5ce \
    "$ROOT/Models/Translation/opus-mt-tc-big-en-ko" \
    config.json generation_config.json model.safetensors source.spm target.spm \
    vocab.json tokenizer_config.json special_tokens_map.json
}

trap 'status=$?; if [[ $status -ne 0 && -n "${CURRENT_PACKAGE:-}" ]]; then emit_package "$CURRENT_PACKAGE" failed "Setup stopped with exit status $status"; fi' EXIT

install_launchers
for item in "${SELECTED[@]}"; do
  CURRENT_PACKAGE="$item"
  emit_package "$item" queued "Waiting to start"
  if group_ready "$item"; then
    emit_package "$item" ready "Already installed; no download needed"
    CURRENT_PACKAGE=""
    continue
  fi
  case "$item" in
    image) install_image ;;
    audio) install_audio ;;
    video) install_video ;;
    music) install_music ;;
    translation) install_translation ;;
  esac
  if ! group_ready "$item"; then
    echo "Required files are still missing for the $item group." >&2
    exit 1
  fi
  emit_package "$item" ready "Installed and verified"
  CURRENT_PACKAGE=""
done

say "Setup complete. Model weights remain under: $ROOT/Models"

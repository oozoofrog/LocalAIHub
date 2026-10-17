# Local AI Studio

[English](README.md) | 한국어

Local AI Studio는 Apple Silicon Mac에서 로컬 이미지·음성·영상·음악 모델과 영어→한국어 번역 모델을 설치하고 실행하는 네이티브 macOS 앱과 CLI입니다. 앱은 선택한 모델 파일과 고정된 버전의 런타임 소스를 별도 저장 폴더에 다운로드합니다. 모델 가중치, 캐시, 생성 미디어, 다운로드한 런타임 체크아웃은 이 Git 저장소에 포함하지 않습니다.

## 요구 사항

- macOS 14 이상을 실행하는 Apple Silicon Mac
- Xcode Command Line Tools
- Qwen Image 그룹 설치에 필요한 CMake
- 설치 중 네트워크 연결
- 선택한 모델 그룹과 런타임 환경을 저장할 디스크 여유 공간

설치를 시작하기 전에 모델 다운로드 예상 용량을 표시합니다. 이미지 약 13 GB, 음성 약 12 GB, 영상 약 16 GB, 음악 약 10 GB이며, 번역은 런타임을 포함해 약 2 GB입니다. 런타임 패키지와 캐시는 추가 공간을 사용합니다. 설치기는 Python 3.12와 Hugging Face 다운로드 도구를 자동으로 준비합니다. 메모리가 24 GB인 Mac에서는 대형 생성 모델을 한 번에 하나만 실행하세요.

## 앱 빌드와 실행

```sh
git clone https://github.com/oozoofrog/LocalAIHub.git
cd LocalAIHub
./script/build_and_run.sh
```

스크립트는 설치 리소스와 빌드에 맞는 `ai` 명령을 포함한 `dist/LocalAIStudio.app` 번들을 만든 뒤 앱을 엽니다. 앱을 추가로 실행하지 않고 번들만 만들려면 `./script/build_and_run.sh build-only`를 사용하세요. Model Setup을 실행하면 선택한 저장 폴더에 실행기와 함께 `ai`를 설치합니다.

처음 실행하면 **Model Setup**에서 저장 폴더와 모델 그룹을 선택하고 다운로드를 시작하세요. `/Volumes/eyedisk/AI` 볼륨이 있으면 해당 경로를 기본 저장 폴더로 사용합니다. 해당 볼륨이 없으면 `~/AI/LocalAIStudio`를 사용합니다. 앱은 Model Setup에서 선택한 폴더를 기억합니다. 설치 화면은 그룹별 준비 상태, 선택한 항목의 다운로드 예상 용량, 볼륨 여유 공간, 확인 가능한 경우 현재 다운로드 진행률, 경과 시간, 설치 활동을 표시합니다. 설치가 완료된 그룹은 다음 설치에서 감지하여 건너뜁니다.

Qwen Image 2.1 가중치를 다운로드하려면 앱에서 Qwen Research License에 동의해야 합니다. 이 라이선스는 사용 범위를 비상업적 연구 또는 평가로 제한합니다. [Qwen 라이선스 확인](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE).

## 명령줄 사용

모델 그룹을 설치하면 선택한 저장 폴더의 `bin` 디렉터리에 `ai` 명령을 설치합니다. 이 Mac의 어느 디렉터리에서나 명령을 사용하려면 같은 소스의 SwiftPM CLI를 `~/.local/bin`에 설치하세요.

```sh
./script/install_global_cli.sh
ai status
ai models
```

스크립트는 셸 프로필을 변경하지 않습니다. `~/.local/bin`이 `PATH`에 없으면 셸 설정에 추가하세요. 기존 전역 `ai`를 갱신하려면 `./script/install_global_cli.sh --replace`를 실행합니다. 이 명령은 이전 실행 파일을 같은 디렉터리에 백업합니다. CLI는 Model Setup에서 선택한 저장 폴더를 사용하며, `AIHUB_ROOT`를 설정하면 해당 경로를 우선합니다. 모델을 실행하기 전에 저장 볼륨을 마운트하세요.

```sh

ai image --prompt "A handmade ceramic teapot in soft morning light" --width 512 --height 512
ai image-edit --image /path/to/reference.png --prompt "Change the background to a sunset beach"
ai tts --text "안녕하세요. 음성 합성 환경을 준비했습니다." --model custom-voice --voice Sohee --language Korean
ai transcribe --audio /path/to/recording.wav --model 1.7b --language Korean --format srt
ai video --prompt "A red panda surfing on a sunny wave" --resolution 512 --frames 17 --steps 30 --memory-mode parallel
ai music --prompt "Warm acoustic indie pop" --lyrics "오늘의 발걸음을 따라" --language ko --duration 30
ai translate --text "The model is ready to use."
```

`ai --help`에서 지원하는 모든 옵션을 확인할 수 있습니다. TTS는 `custom-voice`, `voice-design`(`--instruction` 사용), `clone`(`--reference-audio`와 해당 오디오의 정확한 `--reference-text` 사용)을 지원합니다. 음성 인식 결과는 `txt`, `srt`, `vtt`, `json`으로 저장할 수 있습니다. `ai music --prompt`는 웹 서버 없이 WAV·FLAC·MP3 파일 하나를 생성합니다. MP3 출력에는 `PATH`에 있는 `ffmpeg`가 필요합니다. 옵션 없는 `ai music`은 기존 ACE-Step 페이지를 `127.0.0.1:7860`에서 실행하며, Ctrl-C로 종료합니다. `ai translate`는 `--text` 또는 UTF-8 파일을 지정한 `--input`을 받아 UTF-8 `.txt` 결과를 저장합니다. 기본 출력 파일명에는 타임스탬프를 붙여 구분합니다. 모델 설치나 CLI 사용 가능 상태만으로 추론 완료를 확인할 수는 없습니다. 각 작업이 저장한 실제 결과물을 검증하세요.

## 모델과 런타임 출처

설치기는 `Sources/AIHubCore/Installer/install.sh`에 고정한 리비전으로 모델을 제작자 또는 명시된 커뮤니티 저장소에서 직접 다운로드합니다. 런타임 소스도 고정한 커밋으로 체크아웃합니다. 앱 저장소에는 모델 가중치 사본을 두지 않습니다. 모델·런타임·Python 패키지마다 사용 조건이 다르므로, 사용하기 전에 해당 모델 카드와 라이선스를 확인하세요. [제3자 소프트웨어 고지](THIRD_PARTY_NOTICES.md)를 참고하세요.

앱의 준비 상태 검사는 필요한 로컬 파일과 실행기가 있는지 확인합니다. 다운로드와 빌드가 성공해도 모델이 유용한 결과를 생성했다는 뜻은 아닙니다. 추론 결과는 해당 작업에서 별도로 확인해야 합니다.

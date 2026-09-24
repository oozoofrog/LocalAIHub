import AppKit
import SwiftUI
import AIHubCore

struct GenerationForm {
    var prompt = ""
    var imageWidth = 512
    var imageHeight = 512
    var imageSteps = 20
    var imageSeed = 42
    var imageOutput = ""

    var editImagePath = ""
    var editSteps = 20
    var editSeed = 42
    var editOutput = ""

    var voiceModel: VoiceModel = .customVoice
    var ttsVoice = "Vivian"
    var ttsLanguage = "Korean"
    var voiceInstruction = ""
    var referenceAudioPath = ""
    var referenceText = ""
    var ttsOutputDirectory = AIPaths.audioOutput.path
    var ttsFilePrefix = ""

    var audioPath = ""
    var asrModel: ASRModel = .large
    var asrLanguage = "Korean"
    var asrContext = ""
    var asrFormat = "txt"
    var asrOutputStem = ""

    var videoResolution = 512
    var videoFrames = 17
    var videoSteps = 30
    var videoSeed = 42
    var videoMemoryMode = "parallel"
    var videoOutput = ""

    var musicPrompt = ""
    var musicLyrics = ""
    var musicInstrumental = false
    var musicLanguage = "ko"
    var musicDuration = 30
    var musicBPM = 0
    var musicSeed = -1
    var musicFormat = "wav"
    var musicOutput = ""

    var translationUsesFile = false
    var translationText = ""
    var translationInputPath = ""
    var translationOutput = ""
}

struct CapabilityFormView: View {
    let capability: Capability
    @Binding var form: GenerationForm
    @ObservedObject var runner: ModelRunner
    let setupIsRunning: Bool
    let onRun: (Capability) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch capability {
            case .overview:
                EmptyView()
            case .setup:
                EmptyView()
            case .image:
                imageForm
            case .imageEdit:
                imageEditForm
            case .speech:
                speechForm
            case .transcription:
                transcriptionForm
            case .video:
                videoForm
            case .music:
                musicForm
            case .translation:
                translationForm
            }

            HStack(alignment: .center, spacing: 12) {
                Label("이 Mac에서 실행", systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: run) {
                    Label(runner.isRunning ? "작업 진행 중" : actionTitle, systemImage: runner.isRunning ? "hourglass" : "sparkles")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(runner.isRunning || setupIsRunning)
            }
        }
    }

    private var imageForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard(title: "이미지 설명", subtitle: "Qwen Image 2.1 · 첫 실행에는 512×512를 권장합니다.") {
                PromptEditor(text: $form.prompt, promptLabel: "프롬프트", placeholder: "나무 탁자 위 작은 도자기 주전자, 부드러운 아침 햇살…")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], alignment: .leading, spacing: 12) {
                    Picker("너비", selection: $form.imageWidth) {
                        ForEach([512, 768, 1024], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    Picker("높이", selection: $form.imageHeight) {
                        ForEach([512, 768, 1024], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    Stepper("단계: \(form.imageSteps)", value: $form.imageSteps, in: 1...50)
                    Stepper("시드: \(form.imageSeed)", value: $form.imageSeed, in: 0...Int.max)
                }
                PathField(title: "출력 파일 (선택)", path: $form.imageOutput, mode: .saveFile, placeholder: "이미지 출력 폴더에 PNG로 저장")
            }
            licenseNote
        }
    }

    private var imageEditForm: some View {
        SectionCard(title: "원본과 변경 내용", subtitle: "원본 이미지를 참조해 편집하고 PNG로 저장합니다.") {
            PathField(title: "원본 이미지", path: $form.editImagePath, mode: .openFile, placeholder: "이미지 선택")
            PromptEditor(text: $form.prompt, promptLabel: "변경할 내용", placeholder: "피사체는 유지하고 배경을 해질녘 바닷가로 바꿔주세요…")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], alignment: .leading, spacing: 12) {
                Stepper("단계: \(form.editSteps)", value: $form.editSteps, in: 1...50)
                Stepper("시드: \(form.editSeed)", value: $form.editSeed, in: 0...Int.max)
            }
            PathField(title: "출력 파일 (선택)", path: $form.editOutput, mode: .saveFile, placeholder: "이미지 출력 폴더에 PNG로 저장")
            licenseNote
        }
    }

    private var speechForm: some View {
        SectionCard(title: "음성 설정", subtitle: "Qwen3-TTS · 음성 모델과 언어를 선택합니다.") {
            Picker("음성 모델", selection: $form.voiceModel) {
                ForEach(VoiceModel.allCases) { model in
                    Text(model == .customVoice ? "CustomVoice · 기본 화자" : model == .voiceDesign ? "VoiceDesign · 목소리 설명" : "Base · 참조 오디오")
                        .tag(model)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], alignment: .leading, spacing: 12) {
                TextField("언어", text: $form.ttsLanguage)
                    .frame(maxWidth: 210)
                if form.voiceModel == .customVoice {
                    Picker("화자", selection: $form.ttsVoice) {
                        Text("Vivian").tag("Vivian")
                        Text("Ryan").tag("Ryan")
                    }
                    .frame(maxWidth: 220)
                }
            }
            if form.voiceModel == .voiceDesign {
                TextField("목소리 설명", text: $form.voiceInstruction, prompt: Text("낮고 차분한 한국어 목소리"))
            } else if form.voiceModel == .clone {
                PathField(title: "참조 오디오", path: $form.referenceAudioPath, mode: .openFile, placeholder: "사용 권한이 있는 오디오 선택")
                PromptEditor(text: $form.referenceText, promptLabel: "정확한 대본", placeholder: "참조 오디오에서 말한 내용을 그대로 입력하세요…", minHeight: 74)
            }
            PromptEditor(text: $form.prompt, promptLabel: "읽을 텍스트", placeholder: "안녕하세요. 음성 합성 환경을 준비했습니다.", minHeight: 112)
            PathField(title: "출력 폴더", path: $form.ttsOutputDirectory, mode: .directory, placeholder: AIPaths.audioOutput.path)
            TextField("파일 이름 앞부분 (선택)", text: $form.ttsFilePrefix, prompt: Text("비우면 고유한 시간 이름 사용"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
        }
    }

    private var transcriptionForm: some View {
        SectionCard(title: "받아쓰기 설정", subtitle: "Qwen3-ASR · 가벼운 실행에는 0.6B 모델을 선택하세요.") {
            PathField(title: "오디오 파일", path: $form.audioPath, mode: .openFile, placeholder: "녹음 파일 선택")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                Picker("모델 크기", selection: $form.asrModel) {
                    ForEach(ASRModel.allCases) { model in
                        Text(model == .large ? "1.7B · 높은 정확도" : "0.6B · 가벼운 실행")
                            .tag(model)
                    }
                }
                .frame(maxWidth: 260)
                TextField("언어", text: $form.asrLanguage)
                    .frame(maxWidth: 220)
                Picker("형식", selection: $form.asrFormat) {
                    ForEach(["txt", "srt", "vtt", "json"], id: \.self) { Text($0.uppercased()).tag($0) }
                }
                .frame(maxWidth: 150)
            }
            TextField("문맥 · 고유어 (선택)", text: $form.asrContext)
            PathField(title: "출력 파일 이름", path: $form.asrOutputStem, mode: .saveFile, placeholder: "선택한 형식의 확장자가 붙습니다")
        }
    }

    private var videoForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard(title: "비디오 설명", subtitle: "Lance-3B Video · 첫 실행에는 512×512, 17프레임, 30단계를 권장합니다.") {
                PromptEditor(text: $form.prompt, promptLabel: "프롬프트", placeholder: "햇살 아래 파도를 타는 붉은 판다…")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                    Picker("해상도", selection: $form.videoResolution) {
                        ForEach([512, 640, 768], id: \.self) { Text("\($0) × \($0)").tag($0) }
                    }
                    Picker("프레임", selection: $form.videoFrames) {
                        ForEach([1, 5, 9, 13, 17, 21, 25], id: \.self) { Text("\($0)프레임").tag($0) }
                    }
                    Stepper("단계: \(form.videoSteps)", value: $form.videoSteps, in: 1...60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                    Stepper("시드: \(form.videoSeed)", value: $form.videoSeed, in: 0...Int.max)
                    Picker("메모리", selection: $form.videoMemoryMode) {
                        Text("병렬 · 기본값").tag("parallel")
                        Text("자동").tag("auto")
                        Text("순차 · 낮은 최대 사용량").tag("relay")
                    }
                    .frame(maxWidth: 290)
                }
                PathField(title: "출력 파일 (선택)", path: $form.videoOutput, mode: .saveFile, placeholder: "비디오 출력 폴더에 MP4로 저장")
            }
            SectionCard(title: "자원 사용", subtitle: "15.6 GB BF16 비디오 모델은 메모리를 많이 사용합니다.") {
                Label("시작 전에 다른 대형 생성 작업을 마치세요. 앱은 한 번에 하나의 작업을 실행합니다.", systemImage: "memorychip")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var musicForm: some View {
        SectionCard(title: "입력", subtitle: "ACE-Step 1.5 · 곡을 앱 안에서 직접 생성합니다.") {
            PromptEditor(text: $form.musicPrompt, promptLabel: "곡의 분위기", placeholder: "잔잔한 인디 팝, 따뜻한 기타와 부드러운 드럼…")
            Picker("보컬", selection: $form.musicInstrumental) {
                Text("보컬 포함").tag(false)
                Text("연주곡 요청").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            if form.musicInstrumental {
                Text("연주곡 요청은 프롬프트 지시로 전달되며 모델 출력에 따라 보컬이 포함될 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                PromptEditor(text: $form.musicLyrics, promptLabel: "가사 (선택)", placeholder: "가사를 입력하거나 비워두면 모델이 제안합니다.", minHeight: 92)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                Picker("언어", selection: $form.musicLanguage) {
                    Text("한국어").tag("ko")
                    Text("영어").tag("en")
                    Text("자동").tag("unknown")
                }
                Picker("길이", selection: $form.musicDuration) {
                    ForEach([30, 60, 120], id: \.self) { Text("\($0)초").tag($0) }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                TextField("BPM · 0은 자동", value: $form.musicBPM, format: .number)
                    .textFieldStyle(.roundedBorder)
                TextField("시드 · -1은 무작위", value: $form.musicSeed, format: .number)
                    .textFieldStyle(.roundedBorder)
                Picker("형식", selection: $form.musicFormat) {
                    Text("WAV").tag("wav")
                    Text("FLAC").tag("flac")
                    Text("MP3").tag("mp3")
                }
                .frame(maxWidth: 125)
            }
            PathField(title: "출력 파일 (선택)", path: $form.musicOutput, mode: .saveFile, placeholder: "고유한 이름으로 Music 폴더에 저장")
            if form.musicFormat == "mp3" {
                Label("MP3 저장에는 로컬 ffmpeg가 필요합니다.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var translationForm: some View {
        SectionCard(title: "영어에서 한국어로", subtitle: "OPUS-MT를 로컬에서 실행하고 UTF-8 텍스트 파일로 저장합니다.") {
            Picker("원문", selection: $form.translationUsesFile) {
                Text("텍스트").tag(false)
                Text("파일").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            if form.translationUsesFile {
                PathField(title: "영어 원문 파일", path: $form.translationInputPath, mode: .openFile, placeholder: "UTF-8 텍스트 파일 선택")
            } else {
                PromptEditor(text: $form.translationText, promptLabel: "영어 원문", placeholder: "번역할 텍스트를 입력하세요…")
            }
            PathField(title: "출력 파일 (선택)", path: $form.translationOutput, mode: .saveFile, placeholder: "번역 출력 폴더에 TXT로 저장")
        }
    }

    private var licenseNote: some View {
        Label("Qwen Image 2.1은 비상업적 연구·평가용 Qwen Research License가 적용됩니다.", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var actionTitle: String {
        switch capability {
        case .overview: "모델 실행"
        case .setup: "모델 설치"
        case .image: "이미지 만들기"
        case .imageEdit: "편집 시작"
        case .speech: "음성 만들기"
        case .transcription: "받아쓰기 시작"
        case .video: "비디오 만들기"
        case .music: "음악 만들기"
        case .translation: "번역하기"
        }
    }

    private func run() {
        do {
            let spec: CommandSpec
            switch capability {
            case .overview:
                return
            case .setup:
                return
            case .image:
                spec = try ModelLaunchers.imageGenerate(
                    prompt: form.prompt,
                    output: optionalURL(form.imageOutput),
                    width: form.imageWidth,
                    height: form.imageHeight,
                    steps: form.imageSteps,
                    seed: form.imageSeed
                )
            case .imageEdit:
                spec = try ModelLaunchers.imageEdit(
                    image: URL(fileURLWithPath: expanded(form.editImagePath)),
                    prompt: form.prompt,
                    output: optionalURL(form.editOutput),
                    steps: form.editSteps,
                    seed: form.editSeed
                )
            case .speech:
                spec = try ModelLaunchers.textToSpeech(
                    text: form.prompt,
                    model: form.voiceModel,
                    voice: form.ttsVoice,
                    language: form.ttsLanguage,
                    instruction: form.voiceInstruction,
                    referenceAudio: form.referenceAudioPath.isEmpty ? nil : URL(fileURLWithPath: expanded(form.referenceAudioPath)),
                    referenceText: form.referenceText,
                    outputDirectory: URL(fileURLWithPath: expanded(form.ttsOutputDirectory), isDirectory: true),
                    filePrefix: form.ttsFilePrefix
                )
            case .transcription:
                spec = try ModelLaunchers.transcribe(
                    audio: URL(fileURLWithPath: expanded(form.audioPath)),
                    model: form.asrModel,
                    language: form.asrLanguage,
                    context: form.asrContext,
                    format: form.asrFormat,
                    outputStem: optionalURL(form.asrOutputStem)
                )
            case .video:
                spec = try ModelLaunchers.generateVideo(
                    prompt: form.prompt,
                    resolution: form.videoResolution,
                    frames: form.videoFrames,
                    steps: form.videoSteps,
                    seed: form.videoSeed,
                    memoryMode: form.videoMemoryMode,
                    output: optionalURL(form.videoOutput)
                )
            case .music:
                let basePrompt = form.musicPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !basePrompt.isEmpty else {
                    throw AIHubError.invalidArgument("곡의 분위기를 입력하세요.")
                }
                let prompt = form.musicInstrumental
                    ? basePrompt + ", instrumental music without vocals"
                    : basePrompt
                guard prompt.count < 512 else {
                    throw AIHubError.invalidArgument("곡 설명은 511자 미만이어야 합니다.")
                }
                guard form.musicInstrumental || form.musicLyrics.count < 4096 else {
                    throw AIHubError.invalidArgument("가사는 4096자 미만이어야 합니다.")
                }
                spec = try ModelLaunchers.generateMusic(
                    prompt: prompt,
                    lyrics: form.musicInstrumental ? "" : form.musicLyrics,
                    language: form.musicInstrumental ? "unknown" : form.musicLanguage,
                    duration: form.musicDuration,
                    bpm: form.musicBPM == 0 ? nil : form.musicBPM,
                    seed: form.musicSeed,
                    output: musicOutputURL()
                )
            case .translation:
                spec = try ModelLaunchers.translate(
                    text: form.translationUsesFile ? nil : form.translationText,
                    input: form.translationUsesFile ? optionalURL(form.translationInputPath) : nil,
                    output: optionalURL(form.translationOutput)
                )
            }
            onRun(capability)
            runner.start(spec)
        } catch {
            onRun(capability)
            runner.report(error.localizedDescription)
        }
    }

    private func musicOutputURL() -> URL {
        let selected = optionalURL(form.musicOutput)
            ?? AIPaths.timestampedOutput(in: AIPaths.musicOutput, prefix: "music", extension: form.musicFormat)
        return selected.deletingPathExtension().appendingPathExtension(form.musicFormat)
    }

    private func optionalURL(_ path: String) -> URL? {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(fileURLWithPath: expanded(path))
    }

    private func expanded(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}

private struct PromptEditor: View {
    @Binding var text: String
    let promptLabel: String
    let placeholder: String
    var minHeight: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(promptLabel).font(.subheadline.weight(.medium))
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(3...7)
                .textFieldStyle(.plain)
                .padding(11)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.1)))
                .frame(minHeight: minHeight)
        }
    }
}

private struct PathField: View {
    enum Mode: Equatable {
        case openFile
        case directory
        case saveFile
    }

    let title: String
    @Binding var path: String
    let mode: Mode
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 10) {
                TextField(placeholder, text: $path)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                Button("찾아보기…") { choosePath() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func choosePath() {
        switch mode {
        case .openFile, .directory:
            let panel = NSOpenPanel()
            panel.canChooseFiles = mode == .openFile
            panel.canChooseDirectories = mode == .directory
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            if mode == .directory { panel.prompt = "폴더 선택" }
            if panel.runModal() == .OK, let url = panel.url { path = url.path }
        case .saveFile:
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent
            if panel.runModal() == .OK, let url = panel.url { path = url.path }
        }
    }
}

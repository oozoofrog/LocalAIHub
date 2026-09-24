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
}

struct CapabilityFormView: View {
    let capability: Capability
    @Binding var form: GenerationForm
    @ObservedObject var runner: ModelRunner
    let setupIsRunning: Bool

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
            }

            if capability != .music {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: run) {
                        Label(runner.isRunning ? "Model is running" : actionTitle, systemImage: runner.isRunning ? "hourglass" : "play.fill")
                            .frame(minWidth: 174)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(runner.isRunning || setupIsRunning)

                    Text("Runs locally on this Mac. Model startup can take a while.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var imageForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard(title: "Describe the image", subtitle: "Qwen Image 2.1 · 512×512 is a practical first run.") {
                PromptEditor(text: $form.prompt, promptLabel: "Prompt", placeholder: "A small handmade ceramic teapot on a wooden table, soft morning light…")
                HStack(spacing: 18) {
                    Picker("Width", selection: $form.imageWidth) {
                        ForEach([512, 768, 1024], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    Picker("Height", selection: $form.imageHeight) {
                        ForEach([512, 768, 1024], id: \.self) { Text("\($0) px").tag($0) }
                    }
                    Stepper("Steps: \(form.imageSteps)", value: $form.imageSteps, in: 1...50)
                    Spacer()
                    Stepper("Seed: \(form.imageSeed)", value: $form.imageSeed, in: 0...Int.max)
                }
                PathField(title: "Output file (optional)", path: $form.imageOutput, mode: .saveFile, placeholder: "Uses a timestamped PNG in Output/Qwen-Image-2.1")
            }
            licenseNote
        }
    }

    private var imageEditForm: some View {
        SectionCard(title: "Reference and instruction", subtitle: "The edit wrapper uses the reference image projector and writes a PNG.") {
            PathField(title: "Reference image", path: $form.editImagePath, mode: .openFile, placeholder: "Choose an image")
            PromptEditor(text: $form.prompt, promptLabel: "Edit instruction", placeholder: "Preserve the subject and change the background to a sunset beach…")
            HStack(spacing: 18) {
                Stepper("Steps: \(form.editSteps)", value: $form.editSteps, in: 1...50)
                Stepper("Seed: \(form.editSeed)", value: $form.editSeed, in: 0...Int.max)
                Spacer()
            }
            PathField(title: "Output file (optional)", path: $form.editOutput, mode: .saveFile, placeholder: "Uses a timestamped PNG in Output/Qwen-Image-2.1")
            licenseNote
        }
    }

    private var speechForm: some View {
        SectionCard(title: "Speech settings", subtitle: "Qwen3-TTS · all three 1.7B 8-bit variants are installed.") {
            Picker("Voice model", selection: $form.voiceModel) {
                ForEach(VoiceModel.allCases) { model in Text(model.title).tag(model) }
            }
            HStack(spacing: 14) {
                TextField("Language code", text: $form.ttsLanguage)
                    .frame(maxWidth: 210)
                if form.voiceModel == .customVoice {
                    Picker("Speaker", selection: $form.ttsVoice) {
                        Text("Vivian").tag("Vivian")
                        Text("Ryan").tag("Ryan")
                    }
                    .frame(maxWidth: 220)
                }
            }
            if form.voiceModel == .voiceDesign {
                TextField("Voice description", text: $form.voiceInstruction, prompt: Text("Low, calm Korean voice"))
            } else if form.voiceModel == .clone {
                PathField(title: "Reference audio", path: $form.referenceAudioPath, mode: .openFile, placeholder: "Choose audio you have permission to use")
                PromptEditor(text: $form.referenceText, promptLabel: "Exact transcript", placeholder: "Enter the exact words spoken in the reference audio…", minHeight: 74)
            }
            PromptEditor(text: $form.prompt, promptLabel: "Text to speak", placeholder: "안녕하세요. 음성 합성 환경을 준비했습니다.", minHeight: 112)
            PathField(title: "Output folder", path: $form.ttsOutputDirectory, mode: .directory, placeholder: AIPaths.audioOutput.path)
            TextField("File prefix (optional)", text: $form.ttsFilePrefix, prompt: Text("Uses a unique timestamped name"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
        }
    }

    private var transcriptionForm: some View {
        SectionCard(title: "Transcription settings", subtitle: "Qwen3-ASR · choose the smaller 0.6B model for a lighter run.") {
            PathField(title: "Audio file", path: $form.audioPath, mode: .openFile, placeholder: "Choose an audio recording")
            HStack(spacing: 16) {
                Picker("Model size", selection: $form.asrModel) {
                    ForEach(ASRModel.allCases) { model in Text(model.title).tag(model) }
                }
                .frame(maxWidth: 260)
                TextField("Language", text: $form.asrLanguage)
                    .frame(maxWidth: 220)
                Picker("Format", selection: $form.asrFormat) {
                    ForEach(["txt", "srt", "vtt", "json"], id: \.self) { Text($0.uppercased()).tag($0) }
                }
                .frame(maxWidth: 150)
            }
            TextField("Context / hotwords (optional)", text: $form.asrContext)
            PathField(title: "Output filename stem", path: $form.asrOutputStem, mode: .saveFile, placeholder: "A file extension is appended from the selected format")
        }
    }

    private var videoForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionCard(title: "Video prompt", subtitle: "Lance-3B Video · BF16 checkpoint · 512×512, 17 frames, 30 steps is the guide starting point.") {
                PromptEditor(text: $form.prompt, promptLabel: "Prompt", placeholder: "A red panda surfing on a sunny wave…")
                HStack(spacing: 16) {
                    Picker("Resolution", selection: $form.videoResolution) {
                        ForEach([512, 640, 768], id: \.self) { Text("\($0) × \($0)").tag($0) }
                    }
                    Picker("Frames", selection: $form.videoFrames) {
                        ForEach([1, 5, 9, 13, 17, 21, 25], id: \.self) { Text("\($0) frames").tag($0) }
                    }
                    Stepper("Steps: \(form.videoSteps)", value: $form.videoSteps, in: 1...60)
                }
                HStack(spacing: 16) {
                    Stepper("Seed: \(form.videoSeed)", value: $form.videoSeed, in: 0...Int.max)
                    Picker("Memory", selection: $form.videoMemoryMode) {
                        Text("Parallel · guide default").tag("parallel")
                        Text("Auto").tag("auto")
                        Text("Relay · lower peak use").tag("relay")
                    }
                    .frame(maxWidth: 290)
                    Spacer()
                }
                PathField(title: "Output file (optional)", path: $form.videoOutput, mode: .saveFile, placeholder: "Uses a timestamped MP4 in Output/Video")
            }
            SectionCard(title: "Resource use", subtitle: "The 15.6 GB BF16 video model is memory intensive.") {
                Label("Close other large generators before starting. The app runs one operation at a time.", systemImage: "memorychip")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var musicForm: some View {
        SectionCard(title: "ACE-Step 1.5", subtitle: "Music generation runs in the installed local Gradio interface.") {
            Label("Starts the local MLX server at 127.0.0.1:7860. Use its page to enter lyrics, tags, duration, and generation settings.", systemImage: "music.note.list")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("The server stays attached to this app. Stop it here when you are done.", systemImage: "lock.laptopcomputer")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(action: run) {
                    Label(runner.isRunning ? "Server is running" : "Start ACE-Step", systemImage: "play.fill")
                        .frame(minWidth: 174)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(runner.isRunning || setupIsRunning)
                if runner.musicServerStarted {
                    Button("Open in Browser", systemImage: "arrow.up.right.square") { runner.openMusicPage() }
                        .disabled(!runner.musicPageReady)
                }
            }
            if runner.musicServerStarted && !runner.musicPageReady {
                Label("Waiting for ACE-Step to finish initializing…", systemImage: "hourglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var licenseNote: some View {
        Label("Qwen Image 2.1 is under the Qwen Research License for non-commercial research or evaluation.", systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var actionTitle: String {
        switch capability {
        case .overview: "Run model"
        case .setup: "Set up models"
        case .image: "Generate image"
        case .imageEdit: "Edit image"
        case .speech: "Generate speech"
        case .transcription: "Transcribe audio"
        case .video: "Generate video"
        case .music: "Start ACE-Step"
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
                spec = ModelLaunchers.musicServer()
            }
            runner.start(spec)
        } catch {
            runner.report(error.localizedDescription)
        }
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
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(width: 150, alignment: .leading)
            TextField(placeholder, text: $path)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            Button("Browse…") { choosePath() }
                .buttonStyle(.bordered)
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
            if mode == .directory { panel.prompt = "Choose Folder" }
            if panel.runModal() == .OK, let url = panel.url { path = url.path }
        case .saveFile:
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent
            if panel.runModal() == .OK, let url = panel.url { path = url.path }
        }
    }
}

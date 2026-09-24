import Foundation

public enum VoiceModel: String, CaseIterable, Identifiable, Sendable {
    case customVoice = "custom-voice"
    case voiceDesign = "voice-design"
    case clone = "clone"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .customVoice: "CustomVoice · preset voice"
        case .voiceDesign: "VoiceDesign · describe a voice"
        case .clone: "Base · reference audio"
        }
    }

    public var modelPath: String {
        switch self {
        case .customVoice: "Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
        case .voiceDesign: "Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit"
        case .clone: "Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-Base-8bit"
        }
    }
}

public enum ASRModel: String, CaseIterable, Identifiable, Sendable {
    case large = "1.7b"
    case small = "0.6b"

    public var id: String { rawValue }
    public var title: String { self == .large ? "1.7B · higher accuracy" : "0.6B · lighter" }

    public var modelPath: String {
        "Models/MLX-Audio/Qwen3-ASR-\(rawValue == "1.7b" ? "1.7B" : "0.6B")-8bit"
    }
}

public enum ModelLaunchers {
    public static func imageGenerate(
        prompt: String,
        output: URL? = nil,
        width: Int = 512,
        height: Int = 512,
        steps: Int = 20,
        seed: Int = 42
    ) throws -> CommandSpec {
        try requirePrompt(prompt)
        guard width > 0, height > 0, width.isMultiple(of: 32), height.isMultiple(of: 32) else {
            throw AIHubError.invalidArgument("Image width and height must be positive multiples of 32.")
        }
        guard steps > 0 else { throw AIHubError.invalidArgument("Steps must be positive.") }
        let target = output ?? AIPaths.timestampedOutput(in: AIPaths.imageOutput, prefix: "generation", extension: "png")
        try prepareParent(of: target)
        let wrapper = AIPaths.bin.appendingPathComponent("qwen-image-2.1-generate")
        return CommandSpec(
            executable: wrapper,
            arguments: [prompt, target.path],
            environment: ["QWEN_WIDTH": String(width), "QWEN_HEIGHT": String(height), "QWEN_STEPS": String(steps), "QWEN_SEED": String(seed)],
            label: "Generate image · Qwen Image 2.1",
            outputURL: target
        )
    }

    public static func imageEdit(
        image: URL,
        prompt: String,
        output: URL? = nil,
        steps: Int = 20,
        seed: Int = 42
    ) throws -> CommandSpec {
        try requirePrompt(prompt)
        guard FileManager.default.fileExists(atPath: image.path) else {
            throw AIHubError.invalidArgument("Reference image does not exist: \(image.path)")
        }
        guard steps > 0 else { throw AIHubError.invalidArgument("Steps must be positive.") }
        let target = output ?? AIPaths.timestampedOutput(in: AIPaths.imageOutput, prefix: "edit", extension: "png")
        try prepareParent(of: target)
        return CommandSpec(
            executable: AIPaths.bin.appendingPathComponent("qwen-image-2.1-edit"),
            arguments: [image.path, prompt, target.path],
            environment: ["QWEN_STEPS": String(steps), "QWEN_SEED": String(seed)],
            label: "Edit image · Qwen Image 2.1",
            outputURL: target
        )
    }

    public static func textToSpeech(
        text: String,
        model: VoiceModel = .customVoice,
        voice: String = "Vivian",
        language: String = "Korean",
        instruction: String = "",
        referenceAudio: URL? = nil,
        referenceText: String = "",
        outputDirectory: URL = AIPaths.audioOutput,
        filePrefix: String = ""
    ) throws -> CommandSpec {
        try requirePrompt(text, name: "Text")
        try AIPaths.prepareDirectory(outputDirectory)
        let resolvedPrefix = filePrefix.isEmpty ? "qwen3-tts-\(timestampSuffix())" : filePrefix
        var arguments = ["--text", text, "--lang_code", language, "--output_path", outputDirectory.path, "--file_prefix", resolvedPrefix]
        switch model {
        case .customVoice:
            arguments += ["--voice", voice]
        case .voiceDesign:
            try requirePrompt(instruction, name: "Voice description")
            arguments += ["--instruct", instruction]
        case .clone:
            guard let referenceAudio else { throw AIHubError.invalidArgument("Clone mode requires --reference-audio.") }
            guard FileManager.default.fileExists(atPath: referenceAudio.path) else {
                throw AIHubError.invalidArgument("Reference audio does not exist: \(referenceAudio.path)")
            }
            try requirePrompt(referenceText, name: "Reference transcript")
            arguments += ["--ref_audio", referenceAudio.path, "--ref_text", referenceText]
        }
        return CommandSpec(
            executable: AIPaths.bin.appendingPathComponent("qwen3-tts"),
            arguments: arguments,
            environment: ["QWEN3_TTS_MODEL": AIPaths.path(model.modelPath).path],
            label: "Text to speech · Qwen3-TTS",
            outputURL: outputDirectory
        )
    }

    public static func transcribe(
        audio: URL,
        model: ASRModel = .large,
        language: String = "Korean",
        context: String = "",
        format: String = "txt",
        outputStem: URL? = nil
    ) throws -> CommandSpec {
        guard FileManager.default.fileExists(atPath: audio.path) else {
            throw AIHubError.invalidArgument("Audio file does not exist: \(audio.path)")
        }
        let allowedFormats = ["txt", "srt", "vtt", "json"]
        guard allowedFormats.contains(format) else {
            throw AIHubError.invalidArgument("Transcription format must be one of: \(allowedFormats.joined(separator: ", ")).")
        }
        let target = outputStem ?? AIPaths.audioOutput.appendingPathComponent("transcription-\(timestampSuffix())")
        try prepareParent(of: target)
        var arguments = ["--audio", audio.path, "--language", language, "--format", format, "--output-path", target.path]
        if !context.isEmpty { arguments += ["--context", context] }
        return CommandSpec(
            executable: AIPaths.bin.appendingPathComponent("qwen3-asr"),
            arguments: arguments,
            environment: ["QWEN3_ASR_MODEL": AIPaths.path(model.modelPath).path],
            label: "Transcribe audio · Qwen3-ASR",
            outputURL: URL(fileURLWithPath: target.path + "." + format)
        )
    }

    public static func generateVideo(
        prompt: String,
        resolution: Int = 512,
        frames: Int = 17,
        steps: Int = 30,
        seed: Int = 42,
        memoryMode: String = "parallel",
        output: URL? = nil
    ) throws -> CommandSpec {
        try requirePrompt(prompt)
        guard resolution > 0, resolution.isMultiple(of: 32), frames > 0, frames <= 25, (frames - 1).isMultiple(of: 4), steps > 0 else {
            throw AIHubError.invalidArgument("Video resolution must be a positive multiple of 32; use 1, 5, 9, 13, 17, 21, or 25 frames and positive steps.")
        }
        guard ["parallel", "auto", "relay"].contains(memoryMode) else {
            throw AIHubError.invalidArgument("Memory mode must be parallel, auto, or relay.")
        }
        let target = output ?? AIPaths.timestampedOutput(in: AIPaths.videoOutput, prefix: "lance-video", extension: "mp4")
        try prepareParent(of: target)
        return CommandSpec(
            executable: AIPaths.bin.appendingPathComponent("lance-video"),
            arguments: ["--prompt", prompt, "--resolution", String(resolution), "--frames", String(frames), "--steps", String(steps), "--seed", String(seed), "--memory-mode", memoryMode, "--output", target.path],
            label: "Generate video · Lance-3B",
            outputURL: target
        )
    }

    public static func musicServer() -> CommandSpec {
        CommandSpec(
            executable: AIPaths.bin.appendingPathComponent("ace-step"),
            arguments: [],
            environment: ["CHECK_UPDATE": "false"],
            workingDirectory: AIPaths.aceSource,
            label: "ACE-Step 1.5 · local music UI"
        )
    }

    private static func requirePrompt(_ value: String, name: String = "Prompt") throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIHubError.invalidArgument("\(name) must not be empty.")
        }
    }

    private static func prepareParent(of file: URL) throws {
        try AIPaths.prepareDirectory(file.deletingLastPathComponent())
    }

    private static func timestampSuffix() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}

public enum AIHubError: Error, LocalizedError {
    case invalidArgument(String)
    case processUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let message), .processUnavailable(let message): message
        }
    }
}

import Foundation
import AIHubCore

@main
enum AIHubCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("ai: \(error.localizedDescription)\n", stderr)
            exit(2)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            print(help)
            return
        }
        if command == "--help" || command == "-h" || command == "help" {
            print(help)
            return
        }
        if command == "status" {
            guard arguments.count == 1 else { throw CLIError.usage("`ai status` takes no options.") }
            showStatus()
            return
        }
        if command == "models" {
            guard arguments.count == 1 else { throw CLIError.usage("`ai models` takes no options.") }
            showModels()
            return
        }

        let options = try Options(Array(arguments.dropFirst()))
        switch command {
        case "image":
            try options.allow(["prompt", "output", "width", "height", "steps", "seed"])
            let spec = try ModelLaunchers.imageGenerate(
                prompt: options.required("prompt"),
                output: options.url("output"),
                width: options.integer("width", default: 512),
                height: options.integer("height", default: 512),
                steps: options.integer("steps", default: 20),
                seed: options.integer("seed", default: 42)
            )
            try execute(spec)
        case "image-edit":
            try options.allow(["image", "prompt", "output", "steps", "seed"])
            let spec = try ModelLaunchers.imageEdit(
                image: URL(fileURLWithPath: options.required("image")),
                prompt: options.required("prompt"),
                output: options.url("output"),
                steps: options.integer("steps", default: 20),
                seed: options.integer("seed", default: 42)
            )
            try execute(spec)
        case "tts":
            try options.allow(["text", "model", "voice", "language", "instruction", "reference-audio", "reference-text", "output", "prefix"])
            let modelName = options.value("model") ?? VoiceModel.customVoice.rawValue
            guard let model = VoiceModel(rawValue: modelName) else {
                throw CLIError.usage("`--model` must be custom-voice, voice-design, or clone.")
            }
            let spec = try ModelLaunchers.textToSpeech(
                text: options.required("text"),
                model: model,
                voice: options.value("voice") ?? "Vivian",
                language: options.value("language") ?? "Korean",
                instruction: options.value("instruction") ?? "",
                referenceAudio: options.url("reference-audio"),
                referenceText: options.value("reference-text") ?? "",
                outputDirectory: options.url("output") ?? AIPaths.audioOutput,
                filePrefix: options.value("prefix") ?? ""
            )
            try execute(spec)
        case "transcribe":
            try options.allow(["audio", "model", "language", "context", "format", "output"])
            let modelName = options.value("model") ?? ASRModel.large.rawValue
            guard let model = ASRModel(rawValue: modelName) else {
                throw CLIError.usage("`--model` must be 1.7b or 0.6b.")
            }
            let spec = try ModelLaunchers.transcribe(
                audio: URL(fileURLWithPath: options.required("audio")),
                model: model,
                language: options.value("language") ?? "Korean",
                context: options.value("context") ?? "",
                format: options.value("format") ?? "txt",
                outputStem: options.url("output")
            )
            try execute(spec)
        case "video":
            try options.allow(["prompt", "resolution", "frames", "steps", "seed", "memory-mode", "output"])
            let spec = try ModelLaunchers.generateVideo(
                prompt: options.required("prompt"),
                resolution: options.integer("resolution", default: 512),
                frames: options.integer("frames", default: 17),
                steps: options.integer("steps", default: 30),
                seed: options.integer("seed", default: 42),
                memoryMode: options.value("memory-mode") ?? "parallel",
                output: options.url("output")
            )
            try execute(spec)
        case "music":
            try options.allow([])
            try runMusicServer()
        default:
            throw CLIError.usage("Unknown command `\(command)`. Run `ai --help` for commands.")
        }
    }

    private static func execute(_ spec: CommandSpec) throws {
        guard FileManager.default.isExecutableFile(atPath: spec.executable.path) else {
            throw AIHubError.processUnavailable("Launcher is missing or not executable: \(spec.executable.path)")
        }
        print("\(spec.label)")
        if let output = spec.outputURL { print("Output: \(output.path)") }
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        process.environment = processEnvironment(overrides: spec.environment)
        process.currentDirectoryURL = spec.workingDirectory
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.processFailed(spec.label, process.terminationStatus)
        }
    }

    private static func runMusicServer() throws {
        let spec = ModelLaunchers.musicServer()
        guard FileManager.default.isExecutableFile(atPath: spec.executable.path) else {
            throw AIHubError.processUnavailable("ACE-Step launcher is missing: \(spec.executable.path)")
        }
        let url = URL(string: "http://127.0.0.1:7860")!
        if endpointResponds(url) {
            print("ACE-Step is already running at \(url.absoluteString)")
            try openURL(url)
            return
        }

        print("Starting ACE-Step 1.5. The command stays active while the local server runs.")
        print("The browser opens when the server answers at \(url.absoluteString). Press Ctrl-C to stop it.")
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        process.environment = processEnvironment(overrides: spec.environment)
        process.currentDirectoryURL = spec.workingDirectory
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()

        let readyDeadline = Date().addingTimeInterval(600)
        var didOpenBrowser = false
        while process.isRunning && Date() < readyDeadline {
            if endpointResponds(url) {
                try openURL(url)
                didOpenBrowser = true
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        if !didOpenBrowser {
            print("ACE-Step has not responded yet. Open \(url.absoluteString) after startup finishes.")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.processFailed(spec.label, process.terminationStatus)
        }
    }

    private static func endpointResponds(_ url: URL) -> Bool {
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        probe.arguments = ["--fail", "--silent", "--output", "/dev/null", "--max-time", "1", url.absoluteString]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        do {
            try probe.run()
            probe.waitUntilExit()
            return probe.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func openURL(_ url: URL) throws {
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments = [url.absoluteString]
        try opener.run()
        opener.waitUntilExit()
    }

    private static func processEnvironment(overrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(path)"
        overrides.forEach { environment[$0.key] = $0.value }
        return environment
    }

    private static func showModels() {
        print("Installed local model entry points")
        for model in ModelCatalog.checks {
            print("\(model.isReady ? "READY" : "MISSING")  \(model.name)")
        }
        print("\nTTS models: custom-voice, voice-design, clone")
        print("ASR models: 1.7b, 0.6b")
        print("Music generation uses ACE-Step's local Gradio UI.")
    }

    private static func showStatus() {
        print("Local AI root: \(AIPaths.root.path)")
        guard FileManager.default.fileExists(atPath: AIPaths.root.path) else {
            print("Storage is not mounted. Mount /Volumes/eyedisk to use these launchers.")
            return
        }
        for model in ModelCatalog.checks {
            print("\(model.isReady ? "READY" : "MISSING")  \(model.name)")
            for path in model.missingPaths { print("         missing: \(path.path)") }
        }
    }

    private static let help = """
    Local AI command line

    Usage:
      ai status
      ai models
      ai image --prompt TEXT [--output PATH] [--width 512] [--height 512] [--steps 20] [--seed 42]
      ai image-edit --image PATH --prompt TEXT [--output PATH] [--steps 20] [--seed 42]
      ai tts --text TEXT [--model custom-voice|voice-design|clone] [--voice Vivian] [--language Korean]
             [--instruction TEXT] [--reference-audio PATH --reference-text TEXT] [--output DIRECTORY] [--prefix NAME]
      ai transcribe --audio PATH [--model 1.7b|0.6b] [--language Korean] [--context TEXT]
                    [--format txt|srt|vtt|json] [--output STEM]
      ai video --prompt TEXT [--resolution 512] [--frames 17 (5,9,13,17,21,25)] [--steps 30] [--seed 42]
               [--memory-mode parallel|auto|relay] [--output PATH]
      ai music

    `ai music` runs ACE-Step in the foreground, opens its local Gradio page when ready,
    and stops the server when you press Ctrl-C. The macOS app provides the same model
    actions with forms and a live process log.
    """
}

private struct Options {
    private let values: [String: String]

    init(_ arguments: [String]) throws {
        var parsed: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            guard token.hasPrefix("--"), token.count > 2 else {
                throw CLIError.usage("Expected an option such as --prompt; received `\(token)`. ")
            }
            let key = String(token.dropFirst(2))
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw CLIError.usage("Option --\(key) requires a value.")
            }
            guard parsed[key] == nil else { throw CLIError.usage("Option --\(key) was supplied more than once.") }
            parsed[key] = arguments[index + 1]
            index += 2
        }
        values = parsed
    }

    func allow(_ names: Set<String>) throws {
        let unknown = Set(values.keys).subtracting(names)
        guard unknown.isEmpty else {
            throw CLIError.usage("Unknown option(s): \(unknown.sorted().map { "--\($0)" }.joined(separator: ", ")).")
        }
    }

    func value(_ name: String) -> String? { values[name] }

    func required(_ name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else { throw CLIError.usage("Missing required option --\(name).") }
        return value
    }

    func url(_ name: String) -> URL? {
        values[name].map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
    }

    func integer(_ name: String, default defaultValue: Int) throws -> Int {
        guard let value = values[name] else { return defaultValue }
        guard let result = Int(value) else { throw CLIError.usage("--\(name) must be an integer.") }
        return result
    }
}

private enum CLIError: Error, LocalizedError {
    case usage(String)
    case processFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .usage(let message): "\(message)\nRun `ai --help` for usage."
        case .processFailed(let label, let status): "\(label) failed with exit status \(status)."
        }
    }
}

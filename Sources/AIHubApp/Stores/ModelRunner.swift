import AppKit
import Combine
import Foundation
import AIHubCore

@MainActor
final class ModelRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Ready"
    @Published private(set) var log = ""
    @Published private(set) var progress: Double?
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var lastOutputURL: URL?
    @Published private(set) var activeLabel: String?
    @Published private(set) var musicServerStarted = false
    @Published private(set) var musicPageReady = false

    private var process: Process?
    private var outputPipe: Pipe?
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?
    private var progressBuffer = ""

    var elapsedDescription: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    func start(_ spec: CommandSpec) {
        guard !isRunning else { return }
        guard FileManager.default.isExecutableFile(atPath: spec.executable.path) else {
            report("Launcher is missing or not executable: \(spec.executable.path)")
            return
        }

        let child = Process()
        let pipe = Pipe()
        child.executableURL = spec.executable
        child.arguments = spec.arguments
        child.environment = environment(overrides: spec.environment)
        child.currentDirectoryURL = spec.workingDirectory
        child.standardOutput = pipe
        child.standardError = pipe

        activeLabel = spec.label
        lastOutputURL = spec.outputURL
        isRunning = true
        progress = nil
        elapsedSeconds = 0
        progressBuffer = ""
        status = "Starting · \(spec.label)"
        log = "\(spec.label)\n\(spec.displayCommand)\n\n"
        outputPipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.append(text) }
        }
        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor [weak self] in
                self?.finish(status: status)
            }
        }

        do {
            try child.run()
            process = child
            startedAt = Date()
            startTicker()
            if spec.label.contains("ACE-Step") {
                musicServerStarted = true
                musicPageReady = false
                status = "Server process running · http://127.0.0.1:7860"
                append("\nACE-Step UI: http://127.0.0.1:7860\nThe app keeps this local server process attached so Stop can shut it down.\n")
                monitorMusicServer()
            } else {
                status = "Running · \(spec.label)"
            }
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            outputPipe = nil
            process = nil
            isRunning = false
            status = "Could not start"
            append("\n\(error.localizedDescription)\n")
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        status = "Stopping · \(activeLabel ?? "operation")"
        process.terminate()
    }

    func report(_ message: String) {
        status = "Needs attention"
        append("\nError: \(message)\n")
    }

    func openMusicPage() {
        guard musicServerStarted, musicPageReady, let url = URL(string: "http://127.0.0.1:7860") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealOutput() {
        guard let lastOutputURL else { return }
        if FileManager.default.fileExists(atPath: lastOutputURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
        } else {
            NSWorkspace.shared.open(lastOutputURL.deletingLastPathComponent())
        }
    }

    private func finish(status exitStatus: Int32) {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        process = nil
        isRunning = false
        ticker?.cancel()
        ticker = nil
        startedAt = nil
        progress = nil
        musicServerStarted = false
        musicPageReady = false
        status = exitStatus == 0 ? "Finished · \(activeLabel ?? "operation")" : "Failed · exit status \(exitStatus)"
        if exitStatus == 0, let lastOutputURL {
            append("\nFinished successfully.\nOutput: \(lastOutputURL.path)\n")
        } else if exitStatus == 0 {
            append("\nFinished successfully.\n")
        } else {
            append("\nProcess exited with status \(exitStatus).\n")
        }
    }

    private func append(_ text: String) {
        log += text
        progressBuffer += text.replacingOccurrences(of: "\r", with: "\n")
        if progressBuffer.count > 2_000 { progressBuffer = String(progressBuffer.suffix(1_000)) }
        let regex = try? NSRegularExpression(pattern: #"\b\d{1,3}(?:\.\d+)?%"#)
        let range = NSRange(progressBuffer.startIndex..<progressBuffer.endIndex, in: progressBuffer)
        if let match = regex?.matches(in: progressBuffer, range: range).last,
           let matchRange = Range(match.range, in: progressBuffer) {
            let value = Double(progressBuffer[matchRange].dropLast()) ?? 0
            progress = min(max(value / 100, 0), 1)
        }
        if log.count > 80_000 {
            log = String(log.suffix(60_000))
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isRunning, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
            }
        }
    }

    private func monitorMusicServer() {
        Task { [weak self] in
            guard let url = URL(string: "http://127.0.0.1:7860") else { return }
            for _ in 0..<600 {
                guard self?.isRunning == true, self?.musicServerStarted == true else { return }
                var request = URLRequest(url: url)
                request.timeoutInterval = 2
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let response = response as? HTTPURLResponse, (200..<400).contains(response.statusCode) {
                        guard let self else { return }
                        self.musicPageReady = true
                        self.status = "ACE-Step ready · http://127.0.0.1:7860"
                        self.append("ACE-Step responded at http://127.0.0.1:7860\n")
                        return
                    }
                } catch {
                    // The local server is still initializing; retry while its process remains alive.
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self?.append("\nThe local page has not responded after 10 minutes. Check the server log below.\n")
        }
    }

    private func environment(overrides: [String: String]) -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["AIHUB_ROOT"] = AIPaths.root.path
        values["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (values["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        for (key, value) in overrides { values[key] = value }
        return values
    }

    deinit {
        ticker?.cancel()
        process?.terminate()
    }
}

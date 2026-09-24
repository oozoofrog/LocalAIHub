import AppKit
import Combine
import Foundation
import AIHubCore

enum ModelRunState: Equatable {
    case idle
    case running
    case completed
    case failed
    case stopped
}

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
    @Published private(set) var runState: ModelRunState = .idle
    @Published private(set) var stageTitle = "대기 중"
    @Published private(set) var activityDetail = "모델 작업을 시작하면 진행 상태가 여기에 표시됩니다."
    @Published private(set) var stageIndex = 0
    @Published private(set) var errorSummary: String?
    @Published private(set) var completedOutputURL: URL?

    var lastRunSucceeded: Bool? {
        switch runState {
        case .idle, .running: nil
        case .completed: true
        case .failed, .stopped: false
        }
    }

    private var process: Process?
    private var outputPipe: Pipe?
    private var outputReader: Task<Void, Never>?
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?
    private var lineBuffer = ""
    private var runToken = UUID()
    private var stopRequested = false
    private var outputWasDirectory = false
    private var outputDirectorySnapshot: [String: Date] = [:]
    private var outputFilePrefix: String?
    private var outputFileBaseline: (modified: Date?, size: Int?)?
    private var activeExecutableName = ""

    var elapsedDescription: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    func start(_ spec: CommandSpec) {
        guard !isRunning else { return }
        activeLabel = spec.label
        lastOutputURL = spec.outputURL
        completedOutputURL = nil
        errorSummary = nil
        guard FileManager.default.isExecutableFile(atPath: spec.executable.path) else {
            report("Launcher is missing or not executable: \(spec.executable.path)")
            return
        }

        let token = UUID()
        runToken = token
        stopRequested = false
        activeExecutableName = spec.executable.lastPathComponent
        outputWasDirectory = false
        outputDirectorySnapshot = [:]
        outputFilePrefix = nil
        outputFileBaseline = nil
        if let prefixIndex = spec.arguments.firstIndex(of: "--file_prefix"),
           spec.arguments.indices.contains(prefixIndex + 1) {
            outputFilePrefix = spec.arguments[prefixIndex + 1]
        }
        if let output = spec.outputURL {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: output.path, isDirectory: &isDirectory), isDirectory.boolValue {
                outputWasDirectory = true
                outputDirectorySnapshot = directorySnapshot(at: output)
            } else if let values = try? output.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                      values.isRegularFile == true {
                outputFileBaseline = (values.contentModificationDate, values.fileSize)
            }
        }

        let child = Process()
        let pipe = Pipe()
        child.executableURL = spec.executable
        child.arguments = spec.arguments
        child.environment = environment(overrides: spec.environment)
        child.currentDirectoryURL = spec.workingDirectory
        child.standardOutput = pipe
        child.standardError = pipe

        isRunning = true
        runState = .running
        progress = nil
        elapsedSeconds = 0
        lineBuffer = ""
        stageIndex = 0
        stageTitle = "모델 시작 중"
        activityDetail = "로컬 실행 환경을 준비하고 있습니다."
        status = "Starting · \(spec.label)"
        log = "\(spec.label)\n\(spec.displayCommand)\n\n"
        outputPipe = pipe

        child.terminationHandler = { [weak self] child in
            let status = child.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.runToken == token else { return }
                await self.outputReader?.value
                guard self.runToken == token else { return }
                self.finish(status: status)
            }
        }

        do {
            try child.run()
            try? pipe.fileHandleForWriting.close()
            let handle = pipe.fileHandleForReading
            outputReader = Task.detached(priority: .utility) { [weak self] in
                while true {
                    let data = handle.availableData
                    guard !data.isEmpty else { break }
                    let text = String(decoding: data, as: UTF8.self)
                    await MainActor.run { [weak self] in
                        guard let self, self.runToken == token, self.isRunning else { return }
                        self.append(text)
                    }
                }
            }
            process = child
            startedAt = Date()
            startTicker()
            if activeExecutableName == "ace-step" {
                musicServerStarted = true
                musicPageReady = false
                status = "Server process running · http://127.0.0.1:7860"
                stageTitle = "음악 화면 준비 중"
                activityDetail = "로컬 ACE-Step 서버가 시작하고 있습니다."
                append("\nACE-Step UI: http://127.0.0.1:7860\nThe app keeps this local server process attached so Stop can shut it down.\n")
                monitorMusicServer(token: token)
            } else {
                status = "Running · \(spec.label)"
                stageIndex = 1
                stageTitle = "모델 실행 중"
                activityDetail = "모델이 요청을 처리하고 있습니다. 진행률을 제공하지 않는 작업은 완료 때까지 기다려 주세요."
            }
        } catch {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
            outputPipe = nil
            outputReader = nil
            process = nil
            isRunning = false
            status = "Could not start"
            runState = .failed
            stageTitle = "시작하지 못함"
            errorSummary = error.localizedDescription
            activityDetail = error.localizedDescription
            append("\n\(error.localizedDescription)\n")
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        stopRequested = true
        stageTitle = "중지 중"
        activityDetail = "실행 중인 모델 프로세스에 중지를 요청했습니다."
        status = "Stopping · \(activeLabel ?? "operation")"
        process.terminate()
    }

    func report(_ message: String) {
        status = "Needs attention"
        runState = .failed
        stageTitle = "요청을 시작하지 못함"
        activityDetail = message
        errorSummary = message
        completedOutputURL = nil
        append("\nError: \(message)\n")
    }

    func openMusicPage() {
        guard musicServerStarted, musicPageReady, let url = URL(string: "http://127.0.0.1:7860") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealOutput() {
        guard let completedOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([completedOutputURL])
    }

    private func finish(status exitStatus: Int32) {
        try? outputPipe?.fileHandleForReading.close()
        outputPipe = nil
        outputReader = nil
        process = nil
        isRunning = false
        ticker?.cancel()
        ticker = nil
        startedAt = nil
        musicServerStarted = false
        musicPageReady = false
        if exitStatus == 0, let expected = lastOutputURL, let resolved = resolvedOutput(at: expected) {
            completedOutputURL = resolved
            runState = .completed
            status = "Finished · \(activeLabel ?? "operation")"
            stageIndex = 3
            stageTitle = "완료"
            activityDetail = "출력 파일이 저장됐습니다."
            progress = 1
            append("\nFinished successfully.\nOutput: \(resolved.path)\n")
        } else if stopRequested {
            runState = .stopped
            status = "Stopped · \(activeLabel ?? "operation")"
            stageTitle = "중지됨"
            activityDetail = "사용자 요청으로 작업을 중지했습니다."
            progress = nil
            append("\nStopped by request.\n")
        } else if exitStatus != 0 {
            runState = .failed
            status = "Failed · exit status \(exitStatus)"
            stageTitle = "작업 실패"
            errorSummary = "모델 프로세스가 종료 코드 \(exitStatus)로 끝났습니다. 진단 기록에서 원인을 확인하세요."
            activityDetail = errorSummary ?? "작업에 실패했습니다."
            progress = nil
            append("\nProcess exited with status \(exitStatus).\n")
        } else if lastOutputURL != nil {
            runState = .failed
            status = "Output missing · \(activeLabel ?? "operation")"
            stageTitle = "출력을 확인하지 못함"
            errorSummary = "프로세스는 정상 종료됐지만 새 출력 파일을 확인하지 못했습니다."
            activityDetail = errorSummary ?? "출력을 확인하지 못했습니다."
            progress = nil
            append("\nProcess exited successfully but no new output file was found.\n")
        } else {
            runState = .completed
            status = "Finished · \(activeLabel ?? "operation")"
            stageIndex = 3
            stageTitle = "작업 종료"
            activityDetail = "로컬 프로세스가 종료됐습니다."
            progress = 1
            append("\nFinished successfully.\n")
        }
    }

    private func append(_ text: String) {
        log += text
        if isRunning {
            lineBuffer += text.replacingOccurrences(of: "\r", with: "\n")
            let lines = lineBuffer.components(separatedBy: .newlines)
            lineBuffer = String((lines.last ?? "").suffix(1_000))
            for line in lines.dropLast() { consumeActivityLine(line) }
        }
        if log.count > 80_000 {
            log = String(log.suffix(60_000))
        }
    }

    private func consumeActivityLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        let lower = line.lowercased()
        if activeExecutableName == "ace-step-generate",
           line.hasPrefix("["), let close = line.firstIndex(of: "%"),
           let value = Double(line[line.index(after: line.startIndex)..<close]) {
            progress = min(max(value / 100, 0), 1)
            stageIndex = 1
            stageTitle = "음악 생성 중"
            activityDetail = "ACE-Step이 음악을 만들고 있습니다."
        } else if lower.contains("loading ace-step") || lower.hasPrefix("loading lance") {
            stageIndex = 0
            stageTitle = "모델 불러오는 중"
            activityDetail = "모델 가중치를 메모리에 올리고 있습니다."
        } else if lower.hasPrefix("generating ") || lower.contains("sampling") {
            stageIndex = 1
            stageTitle = "모델 실행 중"
            activityDetail = "모델이 요청을 처리하고 있습니다."
        } else if lower.hasPrefix("writing video") || lower.hasPrefix("saved ") {
            stageIndex = 2
            stageTitle = "결과 저장 중"
            activityDetail = "결과를 저장하고 있습니다."
        }
    }

    private func directorySnapshot(at directory: URL) -> [String: Date] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
        )) ?? []
        var result: [String: Date] = [:]
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { continue }
            result[url.lastPathComponent] = values.contentModificationDate ?? .distantPast
        }
        return result
    }

    private func resolvedOutput(at expected: URL) -> URL? {
        let fileManager = FileManager.default
        if outputWasDirectory {
            let urls = (try? fileManager.contentsOfDirectory(
                at: expected, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            )) ?? []
            return urls.compactMap { url -> (URL, Date)? in
                if let outputFilePrefix,
                   !url.lastPathComponent.hasPrefix(outputFilePrefix + "."),
                   !url.lastPathComponent.hasPrefix(outputFilePrefix + "_") { return nil }
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                      values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return nil }
                let modified = values.contentModificationDate ?? .distantPast
                if let previous = outputDirectorySnapshot[url.lastPathComponent], modified <= previous { return nil }
                return (url, modified)
            }.max(by: { $0.1 < $1.1 })?.0
        }
        guard let values = try? expected.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { return nil }
        if let outputFileBaseline,
           outputFileBaseline.modified == values.contentModificationDate,
           outputFileBaseline.size == values.fileSize { return nil }
        return expected
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

    private func monitorMusicServer(token: UUID) {
        Task { [weak self] in
            guard let url = URL(string: "http://127.0.0.1:7860") else { return }
            for _ in 0..<600 {
                guard self?.runToken == token, self?.isRunning == true, self?.musicServerStarted == true else { return }
                var request = URLRequest(url: url)
                request.timeoutInterval = 2
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let response = response as? HTTPURLResponse, (200..<400).contains(response.statusCode) {
                        guard let self else { return }
                        self.musicPageReady = true
                        self.status = "ACE-Step ready · http://127.0.0.1:7860"
                        self.stageIndex = 1
                        self.stageTitle = "음악 화면 준비됨"
                        self.activityDetail = "로컬 ACE-Step 화면을 열 수 있습니다."
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

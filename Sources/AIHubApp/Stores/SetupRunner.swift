import Combine
import Foundation
import AIHubCore

enum PackageSetupState: String {
    case queued
    case installing
    case downloading
    case ready
    case failed
    case stopped

    var title: String {
        switch self {
        case .queued: "Queued"
        case .installing: "Preparing"
        case .downloading: "Downloading"
        case .ready: "Ready"
        case .failed: "Needs attention"
        case .stopped: "Stopped"
        }
    }
}

@MainActor
final class SetupRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Models are ready when installed"
    @Published private(set) var stage = ""
    @Published private(set) var latestActivity = ""
    @Published private(set) var progress: Double?
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var log = ""
    @Published private(set) var packageStates: [String: PackageSetupState] = [:]

    private var process: Process?
    private var outputPipe: Pipe?
    private var outputReader: Task<Void, Never>?
    private var runToken = UUID()
    private var streamBuffer = ""
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?
    private var activePackage: String?
    private var stopRequested = false
    private var stoppingPackage: String?

    var elapsedDescription: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    func start(packages: [ModelPackage], root: URL, acceptQwenResearchLicense: Bool) {
        guard !isRunning, !packages.isEmpty else { return }
        if packages.contains(where: \.requiresQwenResearchLicense), !acceptQwenResearchLicense {
            status = "Accept the Qwen Image research license before downloading it."
            return
        }
        guard let installer = AIPaths.installerURL() else {
            status = "Installer resources are missing"
            append("Installer resource was not found in the app bundle.\n")
            return
        }

        do {
            try AIPaths.configureRoot(root)
            try installPackagedCLI(in: root)
        } catch {
            status = "Could not prepare model storage"
            append("\n\(error.localizedDescription)\n")
            return
        }

        let child = Process()
        let pipe = Pipe()
        let token = UUID()
        runToken = token
        child.executableURL = URL(fileURLWithPath: "/bin/bash")
        child.arguments = [installer.path, "--root", root.path, "--models", packages.map(\.rawValue).joined(separator: ",")]
        if acceptQwenResearchLicense { child.arguments?.append("--accept-qwen-research-license") }
        child.environment = processEnvironment(root: root)
        child.standardOutput = pipe
        child.standardError = pipe

        packageStates = Dictionary(uniqueKeysWithValues: packages.map { ($0.rawValue, .queued) })
        isRunning = true
        status = "Preparing selected models"
        stage = "Starting the installer"
        latestActivity = ""
        progress = nil
        elapsedSeconds = 0
        streamBuffer = ""
        activePackage = nil
        stopRequested = false
        stoppingPackage = nil
        log = "Destination: \(root.path)\nSelected: \(packages.map(\.title).joined(separator: ", "))\n\n"
        outputPipe = pipe

        child.terminationHandler = { [weak self] child in
            let exitStatus = child.terminationStatus
            Task { @MainActor [weak self] in
                guard let self, self.runToken == token else { return }
                await self.outputReader?.value
                guard self.runToken == token else { return }
                self.finish(exitStatus: exitStatus)
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
                        self.receive(text)
                    }
                }
            }
            process = child
            startedAt = Date()
            startTicker()
        } catch {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
            outputPipe = nil
            outputReader = nil
            process = nil
            isRunning = false
            status = "Could not start the installer"
            append("\n\(error.localizedDescription)\n")
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        stopRequested = true
        stoppingPackage = activePackage
        status = "Stopping model setup"
        process.terminate()
    }

    private func receive(_ text: String) {
        streamBuffer += text.replacingOccurrences(of: "\r", with: "\n")
        let lines = streamBuffer.components(separatedBy: .newlines)
        streamBuffer = lines.last ?? ""
        for line in lines.dropLast() { consume(line) }
        if !streamBuffer.isEmpty { consumeProgress(in: streamBuffer) }
    }

    private func consume(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if line.hasPrefix("@@stage\t") {
            stage = String(line.dropFirst("@@stage\t".count))
            status = stage
            progress = nil
            append(stage + "\n")
            return
        }
        if line.hasPrefix("@@package\t") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4 else { return }
            let packageID = parts[1]
            var state = PackageSetupState(rawValue: parts[2])
            if stopRequested && state == .failed { state = .stopped }
            if let state { packageStates[packageID] = state }
            activePackage = state == .ready || state == .failed || state == .stopped ? nil : packageID
            latestActivity = parts[3]
            status = "\(ModelPackage(rawValue: packageID)?.title ?? packageID) · \(state?.title ?? parts[2])"
            progress = nil
            append("\(ModelPackage(rawValue: packageID)?.title ?? packageID): \(parts[3])\n")
            return
        }
        latestActivity = line
        consumeProgress(in: line)
        append(line + "\n")
    }

    private func consumeProgress(in line: String) {
        guard let range = line.range(of: #"\b\d{1,3}(?:\.\d+)?%"#, options: .regularExpression) else { return }
        let value = Double(line[range].dropLast()) ?? 0
        progress = min(max(value / 100, 0), 1)
    }

    private func finish(exitStatus: Int32) {
        if !streamBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            consume(streamBuffer)
        }
        try? outputPipe?.fileHandleForReading.close()
        outputPipe = nil
        outputReader = nil
        process = nil
        isRunning = false
        ticker?.cancel()
        ticker = nil
        startedAt = nil
        if exitStatus == 0 {
            status = "Setup complete"
            stage = "Selected model groups are ready"
        } else if stopRequested {
            if let packageID = stoppingPackage ?? activePackage { packageStates[packageID] = .stopped }
            status = "Setup stopped"
            stage = "Stopped by request"
        } else {
            if let activePackage { packageStates[activePackage] = .failed }
            status = exitStatus == 15 ? "Setup interrupted" : "Setup failed · exit status \(exitStatus)"
            stage = "Review the activity log for the failed step"
        }
        progress = nil
        append(exitStatus == 0 ? "\nSetup complete.\n" : stopRequested ? "\nSetup stopped by request.\n" : "\nSetup ended with exit status \(exitStatus).\n")
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

    private func append(_ text: String) {
        log += text
        if log.count > 80_000 { log = String(log.suffix(60_000)) }
    }

    private func processEnvironment(root: URL) -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["AIHUB_ROOT"] = root.path
        values["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(root.appendingPathComponent("bin").path):" + (values["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        return values
    }

    private func installPackagedCLI(in root: URL) throws {
        guard let bundledCLI = Bundle.main.resourceURL?.appendingPathComponent("ai"),
              FileManager.default.isExecutableFile(atPath: bundledCLI.path) else {
            throw NSError(domain: "LocalAIStudio.Setup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The packaged ai command was not found in the app bundle. Rebuild the app with script/build_and_run.sh."
            ])
        }

        let fileManager = FileManager.default
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: bin, withIntermediateDirectories: true)
        let destination = bin.appendingPathComponent("ai")
        let temporary = bin.appendingPathComponent(".ai-\(UUID().uuidString)")
        do {
            try fileManager.copyItem(at: bundledCLI, to: temporary)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    deinit {
        ticker?.cancel()
        process?.terminate()
    }
}

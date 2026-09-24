import Foundation

public enum AIPaths {
    private struct Configuration: Codable {
        var rootPath: String
    }

    private static let legacyRoot = URL(fileURLWithPath: "/Volumes/eyedisk/AI", isDirectory: true)
    private static let configurationURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Local AI Studio", isDirectory: true)
        .appendingPathComponent("config.json")

    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["AIHUB_ROOT"], !override.isEmpty {
            return standardized(URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true))
        }
        if let data = try? Data(contentsOf: configurationURL),
           let configuration = try? JSONDecoder().decode(Configuration.self, from: data) {
            return standardized(URL(fileURLWithPath: NSString(string: configuration.rootPath).expandingTildeInPath, isDirectory: true))
        }
        if FileManager.default.fileExists(atPath: legacyRoot.path) {
            return legacyRoot
        }
        return standardized(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AI/LocalAIStudio", isDirectory: true))
    }

    public static var bin: URL { root.appendingPathComponent("bin", isDirectory: true) }
    public static var models: URL { root.appendingPathComponent("Models", isDirectory: true) }
    public static var output: URL { root.appendingPathComponent("Output", isDirectory: true) }
    public static var audioOutput: URL { output.appendingPathComponent("Audio", isDirectory: true) }
    public static var imageOutput: URL { output.appendingPathComponent("Qwen-Image-2.1", isDirectory: true) }
    public static var videoOutput: URL { output.appendingPathComponent("Video", isDirectory: true) }
    public static var aceSource: URL { root.appendingPathComponent("Source/ACE-Step-1.5", isDirectory: true) }

    public static func configureRoot(_ url: URL) throws {
        let selectedRoot = standardized(url)
        try FileManager.default.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(Configuration(rootPath: selectedRoot.path))
        try data.write(to: configurationURL, options: .atomic)
    }

    public static func installerURL() -> URL? {
        Bundle.module.url(forResource: "install", withExtension: "sh", subdirectory: "Installer")
    }

    public static func path(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    public static func timestampedOutput(in directory: URL, prefix: String, extension fileExtension: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return directory.appendingPathComponent("\(prefix)-\(formatter.string(from: Date())).\(fileExtension)")
    }

    public static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func standardized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

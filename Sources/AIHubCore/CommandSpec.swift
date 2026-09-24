import Foundation

public struct CommandSpec: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL?
    public let label: String
    public let outputURL: URL?

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        label: String,
        outputURL: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.label = label
        self.outputURL = outputURL
    }

    public var displayCommand: String {
        ([executable.path] + arguments).map(Self.shellDisplay).joined(separator: " ")
    }

    private static func shellDisplay(_ value: String) -> String {
        if value.rangeOfCharacter(from: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"\\$`"))) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

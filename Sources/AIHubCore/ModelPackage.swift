import Foundation

public enum ModelPackage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case image
    case audio
    case video
    case music

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .image: "Qwen Image 2.1"
        case .audio: "Qwen3 speech"
        case .video: "Lance video"
        case .music: "ACE-Step music"
        }
    }

    public var summary: String {
        switch self {
        case .image: "Text-to-image and image editing · includes the Metal runtime"
        case .audio: "Text-to-speech variants and 0.6B / 1.7B transcription"
        case .video: "Lance-3B Video · MLX runtime"
        case .music: "ACE-Step 1.5 · local music server"
        }
    }

    public var sizeEstimate: String {
        switch self {
        case .image: "About 13 GB"
        case .audio: "About 12 GB"
        case .video: "About 16 GB"
        case .music: "About 10 GB"
        }
    }

    public var estimatedGigabytes: Int {
        switch self {
        case .image: 13
        case .audio: 12
        case .video: 16
        case .music: 10
        }
    }

    public var requiresQwenResearchLicense: Bool { self == .image }

    public func isReady(root: URL = AIPaths.root) -> Bool {
        let checkIDs: [String]
        switch self {
        case .image: checkIDs = ["image", "image-edit"]
        case .audio: checkIDs = ["tts", "asr"]
        case .video: checkIDs = ["video"]
        case .music: checkIDs = ["music"]
        }
        let checks = ModelCatalog.checks(root: root)
        return checkIDs.allSatisfy { id in checks.first(where: { $0.id == id })?.isReady == true }
    }

    public static func parseList(_ value: String) throws -> [ModelPackage] {
        let components = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !components.isEmpty, components.allSatisfy({ ModelPackage(rawValue: $0) != nil }) else {
            throw AIHubError.invalidArgument("Choose model groups from: image, audio, video, music.")
        }
        return Array(Set(components.compactMap(ModelPackage.init(rawValue:)))).sorted { $0.rawValue < $1.rawValue }
    }
}

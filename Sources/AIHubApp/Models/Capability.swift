import Foundation

enum Capability: String, CaseIterable, Identifiable, Hashable {
    case overview
    case setup
    case image
    case imageEdit
    case speech
    case transcription
    case video
    case music
    case translation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .setup: "Model setup"
        case .image: "Create image"
        case .imageEdit: "Edit image"
        case .speech: "Text to speech"
        case .transcription: "Transcribe audio"
        case .video: "Create video"
        case .music: "Create music"
        case .translation: "Translate text"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .setup: "arrow.down.circle"
        case .image: "photo.badge.plus"
        case .imageEdit: "wand.and.stars"
        case .speech: "waveform"
        case .transcription: "text.quote"
        case .video: "film"
        case .music: "music.note"
        case .translation: "character.book.closed"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Local models, one place"
        case .setup: "Download and prepare models"
        case .image: "Qwen Image 2.1"
        case .imageEdit: "Qwen Image 2.1"
        case .speech: "Qwen3-TTS"
        case .transcription: "Qwen3-ASR"
        case .video: "Lance-3B Video"
        case .music: "ACE-Step 1.5"
        case .translation: "OPUS-MT · English to Korean"
        }
    }
}

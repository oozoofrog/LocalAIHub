import Foundation

public struct ModelCheck: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let paths: [URL]

    public init(id: String, name: String, paths: [URL]) {
        self.id = id
        self.name = name
        self.paths = paths
    }

    public var isReady: Bool { missingPaths.isEmpty }

    public var missingPaths: [URL] {
        paths.filter { path in
            let resolvedPath = path.standardizedFileURL.resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: resolvedPath.path),
                  let values = try? resolvedPath.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { return true }
            return (values.fileSize ?? 0) == 0
        }
    }
}

public enum ModelCatalog {
    public static var checks: [ModelCheck] { checks(root: AIPaths.root) }

    public static func checks(root: URL) -> [ModelCheck] {
        [
        ModelCheck(id: "image", name: "Qwen Image 2.1 · image generation", paths: [
            root.appendingPathComponent("bin/qwen-image-2.1-generate"),
            root.appendingPathComponent("Source/stable-diffusion.cpp/build/bin/sd-cli"),
            root.appendingPathComponent("Models/Qwen-Image-2.1/diffusion/qwen_image_2.1-Q6_K.gguf"),
            root.appendingPathComponent("Models/Qwen-Image-2.1/text_encoder/Qwen3VL-8B-Instruct-Q4_K_M.gguf"),
            root.appendingPathComponent("Models/Qwen-Image-2.1/vae/qwen_image_2.1_vae_bf16.safetensors"),
            root.appendingPathComponent("Models/Qwen-Image-2.1/LICENSE-Qwen-Image-2.1.txt"),
        ]),
        ModelCheck(id: "image-edit", name: "Qwen Image 2.1 · image edit", paths: [
            root.appendingPathComponent("bin/qwen-image-2.1-edit"),
            root.appendingPathComponent("Source/stable-diffusion.cpp/build/bin/sd-cli"),
            root.appendingPathComponent("Models/Qwen-Image-2.1/diffusion/qwen_image_2.1-Q6_K.gguf"),
            root.appendingPathComponent("Models/Qwen-Image-2.1/text_encoder/Qwen3VL-8B-Instruct-Q4_K_M.gguf"),
            root.appendingPathComponent("Models/Qwen-Image-2.1/vae/qwen_image_2.1_vae_bf16.safetensors"),
            root.appendingPathComponent("Models/Qwen-Image-2.1/text_encoder/mmproj-Qwen3VL-8B-Instruct-F16.gguf"),
        ]),
        ModelCheck(id: "tts", name: "Qwen3-TTS · CustomVoice / VoiceDesign / Base", paths: [
            root.appendingPathComponent("bin/qwen3-tts"),
            root.appendingPathComponent("Environments/mlx-audio-py312/bin/mlx_audio.tts.generate"),
            root.appendingPathComponent("Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit/model.safetensors"),
            root.appendingPathComponent("Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit/model.safetensors"),
            root.appendingPathComponent("Models/MLX-Audio/Qwen3-TTS-12Hz-1.7B-Base-8bit/model.safetensors"),
        ]),
        ModelCheck(id: "asr", name: "Qwen3-ASR · 1.7B / 0.6B", paths: [
            root.appendingPathComponent("bin/qwen3-asr"),
            root.appendingPathComponent("Environments/mlx-audio-py312/bin/mlx_audio.stt.generate"),
            root.appendingPathComponent("Models/MLX-Audio/Qwen3-ASR-1.7B-8bit/model.safetensors"),
            root.appendingPathComponent("Models/MLX-Audio/Qwen3-ASR-0.6B-8bit/model.safetensors"),
        ]),
        ModelCheck(id: "video", name: "Lance-3B Video", paths: [
            root.appendingPathComponent("bin/lance-video"),
            root.appendingPathComponent("Source/lance-mlx/.venv/bin/python"),
            root.appendingPathComponent("Models/Lance-3B-Video-bf16/model.safetensors"),
            root.appendingPathComponent("Models/Lance-3B-Video-bf16/vae.safetensors"),
            root.appendingPathComponent("Models/Lance-3B-Video-bf16/vit.safetensors"),
        ]),
        ModelCheck(id: "music", name: "ACE-Step 1.5 · Gradio", paths: [
            root.appendingPathComponent("bin/ace-step"),
            root.appendingPathComponent("Source/ACE-Step-1.5/start_gradio_ui_macos.sh"),
            root.appendingPathComponent("Environments/ACE-Step-1.5-py312/bin/python"),
            root.appendingPathComponent("Models/ACE-Step-1.5/acestep-v15-turbo/model.safetensors"),
            root.appendingPathComponent("Models/ACE-Step-1.5/acestep-5Hz-lm-1.7B/model.safetensors"),
        ]),
        ]
    }

    public static func check(for id: String) -> ModelCheck? {
        checks.first { $0.id == id }
    }
}

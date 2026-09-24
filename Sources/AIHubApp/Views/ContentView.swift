import AppKit
import SwiftUI
import AIHubCore

struct ContentView: View {
    @State private var selection: Capability? = .overview
    @State private var activeCapability: Capability?
    @StateObject private var runner = ModelRunner()
    @StateObject private var setupRunner = SetupRunner()
    @State private var form = GenerationForm()

    init(initialSelection: Capability = .overview) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        pageHeader
                        switch selection ?? .overview {
                        case .overview: overview
                        case .setup: ModelSetupView(runner: setupRunner, modelIsRunning: runner.isRunning)
                        default: generatorWorkspace(for: selection ?? .image, width: geometry.size.width)
                        }
                    }
                    .frame(maxWidth: 1120, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .background(WorkspacePalette.background)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(WorkspacePalette.accent)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Label("Local AI Studio", systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
            }
            ToolbarItem(placement: .automatic) {
                Label(globalStatus, systemImage: runner.isRunning || setupRunner.isRunning ? "hourglass" : "circle.fill")
                    .font(.caption)
                    .foregroundStyle(runner.isRunning || setupRunner.isRunning ? WorkspacePalette.accent : WorkspacePalette.good)
            }
            ToolbarItem(placement: .automatic) {
                if runner.isRunning || setupRunner.isRunning {
                    Button("중지", systemImage: "stop.fill", role: .destructive) {
                        if setupRunner.isRunning { setupRunner.stop() } else { runner.stop() }
                    }
                    .help("현재 실행 중인 작업 중지")
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("WORKSPACE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                Text("내 Mac에서 만드는 AI")
                    .font(.system(size: 16, weight: .semibold))
                Text("모델과 결과를 한곳에서 관리")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 17)
            .padding(.top, 23)
            .padding(.bottom, 15)

            List(selection: $selection) {
                Section("시작") {
                    sidebarRow(.overview)
                    sidebarRow(.setup)
                }
                Section("만들기") {
                    sidebarRow(.image)
                    sidebarRow(.imageEdit)
                    sidebarRow(.video)
                    sidebarRow(.music)
                    sidebarRow(.speech)
                }
                Section("이해하기") {
                    sidebarRow(.transcription)
                    sidebarRow(.translation)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("저장 위치")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(AIPaths.root.path)
                        .font(.caption2.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(AIPaths.root.path)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
        }
        .frame(minWidth: 210, idealWidth: 232)
        .background(WorkspacePalette.sidebar)
    }

    private func sidebarRow(_ capability: Capability) -> some View {
        Label(capability.workspaceTitle, systemImage: capability.symbol).tag(capability)
    }

    private var globalStatus: String {
        if setupRunner.isRunning { return "모델 설치 중" }
        if runner.isRunning { return "작업 진행 중" }
        return "작업 대기"
    }

    private var pageHeader: some View {
        let capability = selection ?? .overview
        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Local AI Studio / \(capability == .setup ? "모델 관리" : capability == .overview ? "작업 공간" : "생성 도구")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(capability.workspaceTitle)
                    .font(.system(size: 28, weight: .semibold))
                Text(capability.workspaceDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Label(capability.modelName, systemImage: capability.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(WorkspacePalette.panel, in: Capsule())
                .overlay(Capsule().strokeBorder(WorkspacePalette.line))
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionCard(title: "작업 준비", subtitle: "설치된 모델과 저장 폴더를 확인합니다.") {
                HStack(alignment: .top, spacing: 10) {
                    summaryCell(title: "모델 저장 위치", value: AIPaths.root.path)
                    summaryCell(title: "작업 상태", value: globalStatus)
                }
                HStack {
                    Text("\(ModelPackage.allCases.filter { $0.isReady(root: AIPaths.root) }.count)/\(ModelPackage.allCases.count)개 모델 그룹 준비됨")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("모델 관리", systemImage: "arrow.right") { selection = .setup }
                        .buttonStyle(.bordered)
                }
            }

            HStack {
                Text("작업 시작").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("기능 선택").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 12)], spacing: 12) {
                ForEach(Capability.creationCases) { capability in
                    Button { selection = capability } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Image(systemName: capability.symbol)
                                .font(.system(size: 20))
                                .foregroundStyle(WorkspacePalette.accent)
                            Text(capability.workspaceTitle)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(capability.workspaceDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Label("열기", systemImage: "arrow.right")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(WorkspacePalette.accent)
                                .padding(.top, 5)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                        .padding(17)
                        .background(WorkspacePalette.panel, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(WorkspacePalette.line))
                    }
                    .buttonStyle(.plain)
                }
            }

            SectionCard(title: "모델 준비 상태", subtitle: "로컬 런처와 필수 모델 파일을 확인한 결과입니다.") {
                VStack(spacing: 0) {
                    ForEach(Array(ModelPackage.allCases.enumerated()), id: \.element.id) { index, package in
                        let ready = package.isReady(root: AIPaths.root)
                        HStack(spacing: 11) {
                            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(ready ? WorkspacePalette.good : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(package.title).font(.callout.weight(.medium))
                                Text(package.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ready ? "준비됨" : "확인 필요")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ready ? WorkspacePalette.good : .orange)
                        }
                        .padding(.vertical, 10)
                        if index < ModelPackage.allCases.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func summaryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .help(value)
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(12)
        .background(WorkspacePalette.inset, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func generatorWorkspace(for capability: Capability, width: CGFloat) -> some View {
        if width >= 870 {
            HStack(alignment: .top, spacing: 18) {
                generatorInput(for: capability).frame(maxWidth: .infinity)
                resultPanel(for: capability).frame(width: min(350, width * 0.4))
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                generatorInput(for: capability)
                resultPanel(for: capability)
            }
        }
    }

    private func generatorInput(for capability: Capability) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            CapabilityFormView(
                capability: capability,
                form: $form,
                runner: runner,
                setupIsRunning: setupRunner.isRunning,
                onRun: { activeCapability = $0 }
            )
            SectionCard(title: "출력 위치", subtitle: "완료된 결과는 로컬 폴더에 저장됩니다.") {
                HStack(spacing: 9) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(outputDirectory(for: capability).path)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(outputDirectory(for: capability).path)
                    Spacer(minLength: 6)
                    Button("열기") { NSWorkspace.shared.open(outputDirectory(for: capability)) }
                        .buttonStyle(.borderless)
                        .disabled(!FileManager.default.fileExists(atPath: outputDirectory(for: capability).path))
                }
                .padding(10)
                .background(WorkspacePalette.inset, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func resultPanel(for capability: Capability) -> some View {
        RunResultView(capability: capability, runner: runner, activeCapability: activeCapability) {
            selection = $0
        }
    }

    private func outputDirectory(for capability: Capability) -> URL {
        switch capability {
        case .image: selectedDirectory(form.imageOutput, fallback: AIPaths.imageOutput)
        case .imageEdit: selectedDirectory(form.editOutput, fallback: AIPaths.imageOutput)
        case .speech: form.ttsOutputDirectory.isEmpty ? AIPaths.audioOutput : URL(fileURLWithPath: expanded(form.ttsOutputDirectory), isDirectory: true)
        case .transcription: selectedDirectory(form.asrOutputStem, fallback: AIPaths.audioOutput)
        case .video: selectedDirectory(form.videoOutput, fallback: AIPaths.videoOutput)
        case .music: selectedDirectory(form.musicOutput, fallback: AIPaths.musicOutput)
        case .translation: selectedDirectory(form.translationOutput, fallback: AIPaths.translationOutput)
        case .overview, .setup: AIPaths.output
        }
    }

    private func selectedDirectory(_ path: String, fallback: URL) -> URL {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        return URL(fileURLWithPath: expanded(path)).deletingLastPathComponent()
    }

    private func expanded(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}

#if DEBUG
#Preview("음악 작업 공간") {
    ContentView(initialSelection: .music)
        .frame(width: 1120, height: 780)
}
#endif

extension Capability {
    static let creationCases: [Capability] = [.image, .imageEdit, .video, .music, .speech, .transcription, .translation]

    var workspaceTitle: String {
        switch self {
        case .overview: "개요"
        case .setup: "모델 설치"
        case .image: "이미지 생성"
        case .imageEdit: "이미지 편집"
        case .speech: "음성 생성"
        case .transcription: "음성 받아쓰기"
        case .video: "비디오 생성"
        case .music: "음악 생성"
        case .translation: "번역"
        }
    }

    var workspaceDescription: String {
        switch self {
        case .overview: "모델 준비 상태를 확인하고 다음 작업을 시작합니다."
        case .setup: "저장 위치를 확인하고 필요한 모델을 준비합니다."
        case .image: "설명에서 새 이미지를 만듭니다."
        case .imageEdit: "원본 이미지를 선택하고 바꿀 내용을 설명합니다."
        case .speech: "텍스트를 음성 파일로 변환합니다."
        case .transcription: "오디오를 선택해 텍스트로 옮깁니다."
        case .video: "짧은 영상 장면을 문장으로 구성합니다."
        case .music: "곡의 분위기와 가사를 정하고 앱 안에서 결과를 듣습니다."
        case .translation: "영어 텍스트를 한국어로 옮기고 결과를 검토합니다."
        }
    }

    var modelName: String {
        switch self {
        case .overview: "로컬 작업 공간"
        case .setup: "설치 관리자"
        case .image, .imageEdit: "Qwen Image 2.1"
        case .speech: "Qwen3-TTS"
        case .transcription: "Qwen3-ASR"
        case .video: "Lance 3B Video"
        case .music: "ACE-Step 1.5"
        case .translation: "OPUS-MT · 영어 → 한국어"
        }
    }

    var resultSymbol: String {
        switch self {
        case .image, .imageEdit: "photo"
        case .speech, .music: "waveform"
        case .transcription, .translation: "doc.text"
        case .video: "film"
        case .overview, .setup: "doc"
        }
    }
}

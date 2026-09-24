import AppKit
import SwiftUI
import AIHubCore

struct ModelSetupView: View {
    @ObservedObject var runner: SetupRunner
    let modelIsRunning: Bool
    @State private var rootPath = AIPaths.root.path
    @State private var selectedPackages = Set<ModelPackage>()
    @State private var acceptedQwenResearchLicense = false
    @State private var didLoadInitialSelection = false
    @State private var isActivityExpanded = false
    @SceneStorage("modelSetup.lastRunRootPath") private var lastRunRootPath = ""

    private var rootURL: URL {
        URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
    }

    private var missingPackages: [ModelPackage] {
        ModelPackage.allCases.filter { !$0.isReady(root: rootURL) }
    }

    private var selected: [ModelPackage] {
        ModelPackage.allCases.filter { selectedPackages.contains($0) }
    }

    private var selectedGigabytes: Int {
        selected.reduce(0) { $0 + $1.estimatedGigabytes }
    }

    private var hasUnacceptedQwenPackage: Bool {
        selected.contains(where: \.requiresQwenResearchLicense) && !acceptedQwenResearchLicense
    }

    private var availableSpace: String? {
        guard rootURL.path.hasPrefix("/") else { return nil }
        let parent = FileManager.default.fileExists(atPath: rootURL.path)
            ? rootURL
            : rootURL.deletingLastPathComponent()
        guard let capacity = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage else { return nil }
        return ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
    }

    private var setupCompleted: Bool {
        !runner.isRunning && runner.status == "Setup complete" && lastRunRootPath == rootURL.path
    }

    private var hasStoragePath: Bool {
        !rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                setupLeftColumn
                    .frame(minWidth: 340, idealWidth: 500, maxWidth: .infinity, alignment: .topLeading)
                setupRightColumn
                    .frame(minWidth: 300, idealWidth: 380, maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 18) {
                setupLeftColumn
                setupRightColumn
            }
        }
        .onAppear {
            guard !didLoadInitialSelection else { return }
            selectedPackages = Set(missingPackages)
            didLoadInitialSelection = true
        }
        .onChange(of: runner.isRunning) { _, isRunning in
            if !isRunning { selectedPackages = Set(missingPackages) }
        }
        .onChange(of: rootPath) { _, _ in
            if !runner.isRunning { selectedPackages = Set(missingPackages) }
        }
    }

    private var setupLeftColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            storageCard
            packagesCard
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var setupRightColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            installationCard
            storagePolicyCard
            installerActivity
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var storageCard: some View {
        SectionCard(title: "저장 위치", subtitle: "큰 모델 파일을 다운로드하기 전에 대상 디스크를 확인합니다.") {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(WorkspacePalette.accent)
                TextField("모델 저장 폴더", text: $rootPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(runner.isRunning)
                Button("변경…", systemImage: "folder") { chooseFolder() }
                    .disabled(runner.isRunning)
            }
            HStack(alignment: .top, spacing: 10) {
                storageSummary(label: "사용 가능한 공간", value: availableSpace ?? "확인할 수 없음")
                storageSummary(label: "선택한 다운로드", value: "약 \(selectedGigabytes) GB")
            }
        }
    }

    private func storageSummary(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(WorkspacePalette.inset, in: RoundedRectangle(cornerRadius: 8))
    }

    private var packagesCard: some View {
        SectionCard(title: "모델 패키지", subtitle: "기능별 준비 상태를 확인하고 필요한 그룹을 선택합니다.") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ModelPackage.allCases) { package in
                    if package != ModelPackage.allCases.first { Divider() }
                    packageRow(package)
                }
            }
            Label("준비 상태는 선택한 위치의 모델 파일과 실행 도구를 검사한 결과입니다.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var installationCard: some View {
        SectionCard(title: "설치 진행", subtitle: "다운로드와 준비 단계를 한곳에서 확인합니다.") {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: setupCompleted ? "checkmark.circle.fill" : runner.isRunning ? "arrow.down.circle.fill" : "circle.dotted")
                    .foregroundStyle(setupCompleted ? WorkspacePalette.good : runner.isRunning ? WorkspacePalette.accent : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(installationStatus)
                        .font(.callout.weight(.semibold))
                    if runner.isRunning {
                        Text("모델 파일과 실행 환경을 준비하고 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 11) {
                timelineStep("저장 위치 지정", completed: hasStoragePath)
                timelineStep("선택한 모델 설치", completed: setupCompleted, active: runner.isRunning)
                timelineStep("설치 결과 확인", completed: setupCompleted)
            }
            .padding(.vertical, 2)

            installationProgress

            if selected.contains(where: \.requiresQwenResearchLicense) {
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    Toggle(isOn: $acceptedQwenResearchLicense) {
                        Text("Qwen Research License에 동의합니다.")
                            .font(.callout)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(runner.isRunning)
                    Text("이미지 모델 가중치는 게시자의 조건에 따라 비상업적 연구 또는 평가에 한해 사용할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("라이선스 읽기", destination: URL(string: "https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE")!)
                        .font(.caption)
                }
            }

            Divider()
            installationActions
        }
    }

    private var installationStatus: String {
        if runner.isRunning { return friendlyStage }
        if setupCompleted { return "선택한 모델 설치 완료" }
        if !lastRunRootPath.isEmpty && lastRunRootPath != rootURL.path {
            return "저장 위치가 변경되었습니다"
        }
        switch runner.status {
        case "Models are ready when installed": return "설치 시작 전"
        case "Setup stopped": return "사용자 요청으로 설치를 중지했습니다"
        case "Setup interrupted": return "설치가 중단되었습니다"
        case "Accept the Qwen Image research license before downloading it.": return "Qwen 라이선스 동의가 필요합니다"
        case "Installer resources are missing": return "설치 도구를 찾을 수 없습니다"
        case "Could not prepare model storage": return "저장 위치를 준비하지 못했습니다"
        case "Could not start the installer": return "설치 프로그램을 시작하지 못했습니다"
        default: return runner.status.hasPrefix("Setup failed") ? "설치를 완료하지 못했습니다" : "설치 상태를 확인하세요"
        }
    }

    private var activePackage: (package: ModelPackage, state: PackageSetupState)? {
        guard lastRunRootPath == rootURL.path else { return nil }
        for package in ModelPackage.allCases {
            guard let state = runner.packageStates[package.rawValue] else { continue }
            if state == .downloading || state == .installing { return (package, state) }
        }
        return nil
    }

    private var friendlyStage: String {
        if runner.status == "Stopping model setup" { return "설치를 중지하는 중입니다" }
        if let activePackage {
            return activePackage.state == .downloading
                ? "\(packageDisplayName(activePackage.package)) 다운로드 중"
                : "\(packageDisplayName(activePackage.package)) 실행 환경 준비 중"
        }
        let stage = runner.stage.lowercased()
        if stage.contains("uv runtime manager") { return "패키지 관리자 준비 중" }
        if stage.contains("python 3.12") { return "Python 실행 환경 준비 중" }
        if stage.contains("hugging face") { return "모델 다운로드 도구 준비 중" }
        if stage.contains("source") { return "모델 소스 준비 중" }
        if stage.contains("launchers") { return "모델 실행 도구 설치 중" }
        if stage.contains("building") { return "모델 실행 도구 빌드 중" }
        if stage.contains("environment") || stage.contains("runtime") { return "모델 실행 환경 설치 중" }
        return "선택한 모델을 준비하는 중입니다"
    }

    private func timelineStep(_ title: String, completed: Bool = false, active: Bool = false) -> some View {
        let color: Color = completed ? WorkspacePalette.good : active ? WorkspacePalette.accent : .secondary
        return HStack(spacing: 9) {
            Image(systemName: completed ? "checkmark.circle.fill" : active ? "circle.inset.filled" : "circle")
                .frame(width: 16)
            Text(title)
                .font(.caption.weight(active ? .semibold : .regular))
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private var installationProgress: some View {
        if runner.isRunning {
            VStack(alignment: .leading, spacing: 9) {
                if let progress = runner.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("현재 단계 \(Int(progress * 100))% · \(runner.elapsedDescription) 경과")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text("진행 중 · \(runner.elapsedDescription) 경과")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(activePackage?.state == .downloading
                     ? "현재 패키지의 파일을 내려받고 검증하는 중입니다."
                     : "현재 단계가 끝나면 다음 패키지로 진행합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        } else if setupCompleted {
            ProgressView(value: 1)
                .progressViewStyle(.linear)
            Text("선택한 모델 그룹의 설치가 완료되었습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("설치를 시작하면 실제 단계와 진행률이 여기에 표시됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var installationActions: some View {
        if runner.isRunning {
            Button("설치 중지", systemImage: "stop.fill", role: .destructive) { runner.stop() }
                .controlSize(.large)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Button("선택한 모델 설치", systemImage: "arrow.down.circle.fill") {
                    guard !modelIsRunning else { return }
                    lastRunRootPath = rootURL.path
                    runner.start(packages: selected, root: rootURL, acceptQwenResearchLicense: acceptedQwenResearchLicense)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(modelIsRunning || selected.isEmpty || hasUnacceptedQwenPackage || !hasStoragePath)

                Button("미설치 모델 모두 설치") {
                    guard !modelIsRunning else { return }
                    let missing = missingPackages
                    selectedPackages = Set(missing)
                    lastRunRootPath = rootURL.path
                    runner.start(packages: missing, root: rootURL, acceptQwenResearchLicense: acceptedQwenResearchLicense)
                }
                .controlSize(.large)
                .disabled(modelIsRunning || missingPackages.isEmpty || (missingPackages.contains(where: \.requiresQwenResearchLicense) && !acceptedQwenResearchLicense) || !hasStoragePath)

                if modelIsRunning {
                    Label("모델 작업이 끝나면 설치를 시작할 수 있습니다.", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
                if hasUnacceptedQwenPackage {
                    Label("Qwen Image 2.1을 설치하려면 라이선스에 동의하세요.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
        }
    }

    private var storagePolicyCard: some View {
        SectionCard(title: "저장 정책") {
            Label("모델, 실행 환경, 캐시, 생성 파일은 선택한 저장 위치에 놓입니다. 앱 소스와 모델 가중치는 별도로 관리합니다.", systemImage: "internaldrive")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("모델 다운로드는 고정된 소스 리비전과 Hugging Face 파일 검증을 사용합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var installerActivity: some View {
        if !runner.log.isEmpty {
            DisclosureGroup("설치 진단 로그", isExpanded: $isActivityExpanded) {
                ScrollView {
                    Text(runner.log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 110, maxHeight: 240)
                .background(WorkspacePalette.inset, in: RoundedRectangle(cornerRadius: 9))
                .padding(.top, 8)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 4)
        }
    }

    private func packageRow(_ package: ModelPackage) -> some View {
        let isReady = package.isReady(root: rootURL)
        let setupState = lastRunRootPath == rootURL.path ? runner.packageStates[package.rawValue] : nil
        let statusTitle: String
        let statusColor: Color
        if setupState == .failed {
            statusTitle = "확인 필요"
            statusColor = .red
        } else if setupState == .stopped {
            statusTitle = "중지됨"
            statusColor = .orange
        } else if setupState == .installing || setupState == .downloading {
            statusTitle = setupState == .downloading ? "다운로드 중" : "준비 중"
            statusColor = .orange
        } else if isReady {
            statusTitle = "준비됨"
            statusColor = WorkspacePalette.good
        } else if setupState == .ready {
            statusTitle = "파일 확인 필요"
            statusColor = .orange
        } else if setupState == .queued {
            statusTitle = "대기 중"
            statusColor = .secondary
        } else {
            statusTitle = "설치 필요"
            statusColor = .secondary
        }

        return Toggle(isOn: packageBinding(package)) {
            HStack(spacing: 12) {
                Image(systemName: isReady ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(isReady ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(packageDisplayName(package)).font(.body.weight(.semibold))
                        Text(statusTitle)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor)
                    }
                    Text(packageDisplaySummary(package))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("약 \(package.estimatedGigabytes) GB")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.vertical, 5)
        }
        .toggleStyle(.checkbox)
        .disabled(runner.isRunning)
    }

    private func packageDisplayName(_ package: ModelPackage) -> String {
        switch package {
        case .image: "Qwen Image 2.1"
        case .audio: "Qwen3 음성"
        case .video: "Lance 비디오"
        case .music: "ACE-Step 음악"
        case .translation: "영어 → 한국어 번역"
        }
    }

    private func packageDisplaySummary(_ package: ModelPackage) -> String {
        switch package {
        case .image: "이미지 생성·편집 및 Metal 실행 환경"
        case .audio: "음성 합성·받아쓰기 모델과 MLX 실행 환경"
        case .video: "Lance-3B 비디오와 MLX 실행 환경"
        case .music: "ACE-Step 1.5 직접 생성 및 로컬 웹 UI"
        case .translation: "OPUS-MT 로컬 텍스트 번역"
        }
    }

    private func packageBinding(_ package: ModelPackage) -> Binding<Bool> {
        Binding(
            get: { selectedPackages.contains(package) },
            set: { isSelected in
                if isSelected { selectedPackages.insert(package) }
                else { selectedPackages.remove(package) }
            }
        )
    }

    @MainActor
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "모델 저장 폴더 선택"
        panel.prompt = "이 폴더 사용"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
        }
    }
}

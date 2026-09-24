import AppKit
import SwiftUI
import AIHubCore

struct ModelSetupView: View {
    @ObservedObject var runner: SetupRunner
    @State private var rootPath = AIPaths.root.path
    @State private var selectedPackages = Set<ModelPackage>()
    @State private var acceptedQwenResearchLicense = false
    @State private var didLoadInitialSelection = false
    @State private var isActivityExpanded = false

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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionCard(title: "Choose where models live", subtitle: "Downloads, runtimes, caches, and generated files stay outside the project and Git repository.") {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive")
                        .foregroundStyle(.secondary)
                    TextField("Model storage folder", text: $rootPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(runner.isRunning)
                    Button("Choose…", systemImage: "folder") { chooseFolder() }
                        .disabled(runner.isRunning)
                }
                HStack {
                    Label(availableSpace.map { "\($0) available on this volume" } ?? "Available space unknown", systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Selected downloads: about \(selectedGigabytes) GB")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(selectedGigabytes > 0 ? .primary : .secondary)
                }
            }

            SectionCard(title: "Model groups", subtitle: "Select only the groups you need. Existing complete installs are detected and skipped.") {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(ModelPackage.allCases) { package in
                        packageRow(package)
                    }
                }
            }

            if selected.contains(where: \.requiresQwenResearchLicense) {
                SectionCard(title: "Qwen Image 2.1 license", subtitle: "The selected image weights are limited to non-commercial research or evaluation by the publisher's license.") {
                    Toggle(isOn: $acceptedQwenResearchLicense) {
                        Text("I accept the Qwen Research License for this download.")
                            .font(.callout)
                    }
                    .toggleStyle(.checkbox)
                    .disabled(runner.isRunning)
                    Link("Read the license", destination: URL(string: "https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE")!)
                        .font(.callout)
                }
            }

            if runner.isRunning {
                setupProgress
            } else {
                SectionCard(title: runner.status, subtitle: "Model downloads use pinned source revisions and Hugging Face file verification.") {
                    HStack(spacing: 10) {
                        Button("Download Selected", systemImage: "arrow.down.circle.fill") {
                            runner.start(packages: selected, root: rootURL, acceptQwenResearchLicense: acceptedQwenResearchLicense)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(selected.isEmpty || hasUnacceptedQwenPackage || rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Download All Missing") {
                            let missing = missingPackages
                            selectedPackages = Set(missing)
                            runner.start(packages: missing, root: rootURL, acceptQwenResearchLicense: acceptedQwenResearchLicense)
                        }
                        .controlSize(.large)
                        .disabled(missingPackages.isEmpty || (missingPackages.contains(where: \.requiresQwenResearchLicense) && !acceptedQwenResearchLicense) || rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if hasUnacceptedQwenPackage {
                        Label("Accept the Qwen Research License to include Qwen Image 2.1.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !runner.log.isEmpty {
                DisclosureGroup("Installer activity", isExpanded: $isActivityExpanded) {
                    ScrollView {
                        Text(runner.log)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minHeight: 110, maxHeight: 240)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .padding(.top, 8)
                }
                .font(.callout.weight(.medium))
                .padding(.horizontal, 4)
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

    private func packageRow(_ package: ModelPackage) -> some View {
        let isReady = package.isReady(root: rootURL)
        let setupState = runner.packageStates[package.rawValue]
        let statusTitle: String
        let statusColor: Color
        if setupState == .failed {
            statusTitle = "Needs attention"
            statusColor = .red
        } else if setupState == .installing || setupState == .downloading {
            statusTitle = setupState?.title ?? "Working"
            statusColor = .orange
        } else if isReady || setupState == .ready {
            statusTitle = "Ready"
            statusColor = .green
        } else if setupState == .queued {
            statusTitle = "Queued"
            statusColor = .secondary
        } else {
            statusTitle = "Needs download"
            statusColor = .secondary
        }

        return Toggle(isOn: packageBinding(package)) {
            HStack(spacing: 12) {
                Image(systemName: isReady ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(isReady ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(package.title).font(.body.weight(.semibold))
                        Text(statusTitle.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(statusColor)
                    }
                    Text(package.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(package.sizeEstimate)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.vertical, 5)
        }
        .toggleStyle(.checkbox)
        .disabled(runner.isRunning)
    }

    private var setupProgress: some View {
        SectionCard(title: runner.status, subtitle: runner.stage) {
            if let progress = runner.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(runner.latestActivity.isEmpty ? "Preparing the selected model groups" : runner.latestActivity)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    Text("\(runner.elapsedDescription) elapsed · Keep this window open while setup runs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop", systemImage: "stop.fill", role: .destructive) { runner.stop() }
                    .disabled(!runner.isRunning)
            }
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
        panel.title = "Choose model storage folder"
        panel.prompt = "Use This Folder"
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

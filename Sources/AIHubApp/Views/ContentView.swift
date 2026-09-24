import SwiftUI
import AppKit
import AIHubCore

struct ContentView: View {
    @State private var selection: Capability? = .overview
    @StateObject private var runner = ModelRunner()
    @StateObject private var setupRunner = SetupRunner()
    @State private var form = GenerationForm()

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LOCAL AI")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                    Text("Studio")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 15)
                .padding(.top, 16)

                List(selection: $selection) {
                    Section("Models") {
                        Label(Capability.setup.title, systemImage: Capability.setup.symbol)
                            .tag(Capability.setup)
                        ForEach(Capability.allCases) { capability in
                            if capability != .setup {
                            Label(capability.title, systemImage: capability.symbol)
                                .tag(capability)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)

                HStack(spacing: 8) {
                    Circle()
                        .fill(FileManager.default.fileExists(atPath: AIPaths.root.path) ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(FileManager.default.fileExists(atPath: AIPaths.root.path) ? AIPaths.root.path : "Choose model storage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .frame(minWidth: 210, idealWidth: 236)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    pageHeader
                    if selection == .overview {
                        overview
                    } else if selection == .setup {
                        ModelSetupView(runner: setupRunner)
                    } else {
                        CapabilityFormView(capability: selection ?? .overview, form: $form, runner: runner, setupIsRunning: setupRunner.isRunning)
                    }
                    if selection != .setup { processCard }
                }
                .frame(maxWidth: 920, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if runner.isRunning || setupRunner.isRunning {
                    Button("Stop", systemImage: "stop.fill", role: .destructive) {
                        if setupRunner.isRunning { setupRunner.stop() } else { runner.stop() }
                    }
                        .help("Stop the running model or local server")
                }
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text((selection ?? .overview).title)
                    .font(.system(size: 31, weight: .semibold, design: .rounded))
                Text((selection ?? .overview).subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            let isBusy = runner.isRunning || setupRunner.isRunning
            Label(isBusy ? "Busy" : "Ready", systemImage: isBusy ? "hourglass" : "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isBusy ? Color.orange.opacity(0.14) : Color.green.opacity(0.14), in: Capsule())
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                OverviewMetric(title: "Model groups", value: "4", detail: "image · speech · video · music")
                OverviewMetric(title: "Model storage", value: FileManager.default.fileExists(atPath: AIPaths.root.path) ? "Available" : "Not found", detail: AIPaths.root.path)
                OverviewMetric(title: "Outputs", value: "Local", detail: AIPaths.output.path)
            }
            SectionCard(title: "Installed models", subtitle: "Readiness is based on the local launcher and model files.") {
                VStack(spacing: 0) {
                    ForEach(Array(ModelCatalog.checks.enumerated()), id: \.element.id) { index, check in
                        HStack(spacing: 12) {
                            Image(systemName: check.isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(check.isReady ? Color.green : Color.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(check.name).font(.body.weight(.medium))
                                Text(check.isReady ? "Ready to launch" : "Missing \(check.missingPaths.count) required file(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(check.isReady ? "READY" : "MISSING")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(check.isReady ? Color.green : Color.orange)
                        }
                        .padding(.vertical, 12)
                        if index < ModelCatalog.checks.count - 1 { Divider() }
                    }
                }
                HStack {
                    Text("Need another model group?")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Model Setup", systemImage: "arrow.down.circle") { selection = .setup }
                }
                .padding(.top, 8)
            }
            SectionCard(title: "Resource note", subtitle: "This Mac has \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB of unified memory.") {
                Label("Run only one large generator at a time: Qwen Image, Lance Video, or ACE-Step.", systemImage: "memorychip")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var processCard: some View {
        SectionCard(title: "Activity", subtitle: runner.status) {
            if runner.isRunning {
                HStack {
                    if let progress = runner.progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(runner.elapsedDescription)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .padding(.bottom, 12)
            }
            if runner.musicServerStarted {
                HStack {
                    Text("ACE-Step local interface · 127.0.0.1:7860")
                        .font(.callout.monospaced())
                    Spacer()
                    Button("Open in Browser", systemImage: "arrow.up.right.square") { runner.openMusicPage() }
                }
                .padding(.bottom, 12)
            }
            if let output = runner.lastOutputURL {
                HStack {
                    Label(output.lastPathComponent, systemImage: "doc")
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Button("Show", systemImage: "folder") { runner.revealOutput() }
                        .disabled(runner.isRunning)
                }
                .padding(.bottom, 12)
            }
            ScrollView {
                Text(runner.log.isEmpty ? "Generated output and runtime logs will appear here." : runner.log)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 100, maxHeight: 240)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        }
    }
}

private struct OverviewMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.06)))
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.primary.opacity(0.06)))
    }
}

import AppKit
import AVKit
import SwiftUI

struct RunResultView: View {
    let capability: Capability
    @ObservedObject var runner: ModelRunner
    let activeCapability: Capability?
    let onSelectActive: (Capability) -> Void

    private var isCurrentRun: Bool { activeCapability == capability }

    var body: some View {
        SectionCard(title: "진행 상태와 결과") {
            HStack {
                Label(stateLabel, systemImage: stateSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(stateColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))
                Spacer()
                if isCurrentRun && runner.runState != .idle {
                    Text(runner.elapsedDescription)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if runner.isRunning && !isCurrentRun, let activeCapability {
                emptyWell(symbol: activeCapability.symbol,
                          title: "\(activeCapability.workspaceTitle) 진행 중",
                          detail: "현재 작업이 끝나면 새 작업을 시작할 수 있습니다.")
                Button("진행 화면 보기", systemImage: "arrow.right") {
                    onSelectActive(activeCapability)
                }
                .buttonStyle(.bordered)
            } else if !isCurrentRun || runner.runState == .idle {
                emptyWell(symbol: capability.resultSymbol,
                          title: "아직 결과가 없습니다",
                          detail: "설정을 입력하고 작업을 시작하면 실제 진행 상태와 결과가 여기에 표시됩니다.")
                stageList
            } else {
                runDetails
            }

            if isCurrentRun && !runner.log.isEmpty {
                DisclosureGroup("활동 로그") {
                    ScrollView {
                        Text(runner.log)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 140)
                    .background(WorkspacePalette.inset, in: RoundedRectangle(cornerRadius: 8))
                }
                .font(.caption.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private var runDetails: some View {
        switch runner.runState {
        case .idle:
            EmptyView()
        case .running:
            VStack(alignment: .leading, spacing: 12) {
                emptyWell(symbol: capability.resultSymbol,
                          title: runner.stageTitle.isEmpty ? "모델 실행 중" : runner.stageTitle,
                          detail: runner.activityDetail.isEmpty ? "실행 로그에서 현재 단계를 확인할 수 있습니다." : runner.activityDetail)
                stageList
                if let progress = runner.progress {
                    ProgressView(value: progress)
                        .tint(WorkspacePalette.accent)
                        .accessibilityLabel("작업 진행률")
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("작업 진행 중")
                }
                Button("작업 중지", systemImage: "stop.fill", role: .destructive) {
                    runner.stop()
                }
                .buttonStyle(.bordered)
            }
        case .completed:
            if let output = runner.completedOutputURL {
                ResultFilePreview(url: output)
                stageList
                HStack {
                    Label(output.lastPathComponent, systemImage: "doc")
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WorkspacePalette.good)
                }
                .padding(11)
                .background(WorkspacePalette.inset, in: RoundedRectangle(cornerRadius: 8))
                Button("Finder에서 보기", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                }
                .buttonStyle(.bordered)
            } else {
                emptyWell(symbol: "checkmark.circle",
                          title: "실행이 완료되었습니다",
                          detail: "검증된 결과 파일이 없습니다. 활동 로그에서 저장 위치를 확인하세요.")
                stageList
            }
        case .failed:
            emptyWell(symbol: "exclamationmark.triangle",
                      title: "작업을 완료하지 못했습니다",
                      detail: runner.errorSummary ?? runner.status)
            stageList
        case .stopped:
            emptyWell(symbol: "stop.circle",
                      title: "작업이 중지되었습니다",
                      detail: "필요하면 설정을 조정한 뒤 다시 시작할 수 있습니다.")
            stageList
        }
    }

    private var stateLabel: String {
        guard isCurrentRun else { return runner.isRunning ? "다른 작업 진행 중" : "작업 대기" }
        return switch runner.runState {
        case .idle: "작업 대기"
        case .running: "진행 중"
        case .completed: "완료"
        case .failed: "오류"
        case .stopped: "중지됨"
        }
    }

    private var stateSymbol: String {
        guard isCurrentRun else { return runner.isRunning ? "hourglass" : "circle" }
        return switch runner.runState {
        case .idle: "circle"
        case .running: "hourglass"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .stopped: "stop.circle"
        }
    }

    private var stateColor: Color {
        guard isCurrentRun else { return runner.isRunning ? WorkspacePalette.accent : .secondary }
        return switch runner.runState {
        case .idle: .secondary
        case .running: WorkspacePalette.accent
        case .completed: WorkspacePalette.good
        case .failed: .red
        case .stopped: .orange
        }
    }

    private func emptyWell(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(WorkspacePalette.accent)
                .frame(width: 49, height: 49)
                .background(WorkspacePalette.accentSoft, in: RoundedRectangle(cornerRadius: 14))
            Text(title)
                .font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 185)
        .padding(14)
        .background(WorkspacePalette.inset, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WorkspacePalette.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
    }

    private var stageList: some View {
        let index = isCurrentRun && runner.runState != .idle ? runner.stageIndex : -1
        let isRunning = isCurrentRun && runner.runState == .running
        let saved = isCurrentRun && runner.runState == .completed && runner.completedOutputURL != nil
        return VStack(alignment: .leading, spacing: 10) {
            stage("입력 준비", index: 0, current: index, running: isRunning, done: index >= 0)
            stage("모델 준비", index: 0, current: index, running: isRunning, done: index > 0)
            stage("모델 실행", index: 1, current: index, running: isRunning, done: index > 1)
            stage("파일 저장", index: 2, current: index, running: isRunning, done: saved)
        }
        .padding(.vertical, 3)
    }

    private func stage(_ title: String, index: Int, current: Int, running: Bool, done: Bool) -> some View {
        let active = running && current == index && !done
        return Label(title, systemImage: done ? "checkmark.circle.fill" : active ? "circle.dotted.circle" : "circle")
            .font(.caption.weight(active ? .semibold : .regular))
            .foregroundStyle(done ? WorkspacePalette.good : active ? WorkspacePalette.accent : .secondary)
    }
}

private struct ResultFilePreview: View {
    let url: URL

    var body: some View {
        Group {
            switch url.pathExtension.lowercased() {
            case "png", "jpg", "jpeg", "heic", "webp":
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 270)
                } else {
                    unavailablePreview
                }
            case "wav", "mp3", "flac", "m4a", "mp4", "mov":
                MediaFilePreview(url: url)
                    .frame(height: ["mp4", "mov"].contains(url.pathExtension.lowercased()) ? 220 : 80)
            case "txt", "srt", "vtt", "json":
                ScrollView {
                    Text(Self.textPrefix(at: url))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 210)
            default:
                unavailablePreview
            }
        }
        .background(WorkspacePalette.inset, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WorkspacePalette.line))
        .accessibilityLabel("결과 미리보기")
    }

    private var unavailablePreview: some View {
        Label("미리보기를 지원하지 않는 파일입니다", systemImage: "doc")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }

    private static func textPrefix(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "텍스트 파일을 읽을 수 없습니다." }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8_192) else { return "텍스트 파일을 읽을 수 없습니다." }
        let text = String(decoding: data, as: UTF8.self)
        return data.count == 8_192 ? text + "\n…" : text
    }
}

private struct MediaFilePreview: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var url: URL
        init(url: URL) { self.url = url }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard context.coordinator.url != url else { return }
        view.player?.pause()
        view.player = AVPlayer(url: url)
        context.coordinator.url = url
    }
}

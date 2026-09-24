import AppKit
import SwiftUI

enum WorkspacePalette {
    static let background = adaptive(light: 0xF7F8FA, dark: 0x191D23)
    static let sidebar = adaptive(light: 0xE9EDF2, dark: 0x171B21)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x232830)
    static let inset = adaptive(light: 0xF4F6F8, dark: 0x1D2229)
    static let line = adaptive(light: 0xDBE1E8, dark: 0x343B46)
    static let accent = adaptive(light: 0x324FDB, dark: 0x90A5FF)
    static let accentSoft = adaptive(light: 0xE9EDFF, dark: 0x303A61)
    static let good = adaptive(light: 0x207C64, dark: 0x72D5B5)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkspacePalette.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(WorkspacePalette.line))
    }
}

import SwiftUI
import UIKit

/// 拾贝设计令牌 — 浅灰画布、白色卡片、墨色胶囊、平台色。
enum Theme {
    // MARK: Colors
    static let canvas = dynamic(light: 0xF2F2F7, dark: 0x000000)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surfaceMuted = dynamic(light: 0xF7F7FA, dark: 0x242426)
    static let ink = dynamic(light: 0x0B0B0C, dark: 0xF5F5F7)
    static let inkSecondary = dynamic(light: 0x6E6E73, dark: 0xA1A1A6)
    static let inkTertiary = dynamic(light: 0xA1A1A6, dark: 0x6E6E73)
    static let hairline = dynamic(light: 0xEDEDF0, dark: 0x2C2C2E)
    static let fill = dynamic(light: 0xE8E8ED, dark: 0x2C2C2E)
    static let onAccent = Color.white
    static let success = dynamic(light: 0x2BA24C, dark: 0x34C759)
    static let warning = dynamic(light: 0xC77700, dark: 0xFF9F0A)
    static let danger = dynamic(light: 0xE6162D, dark: 0xFF453A)

    // MARK: Metrics
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let gridSpacing: CGFloat = 4
    static let screenPadding: CGFloat = 16

    // MARK: Type
    static func wordmark() -> Font {
        .system(size: 21, weight: .semibold, design: .serif)
    }
    static func cardTitle() -> Font {
        .system(size: 16, weight: .semibold)
    }
    static func body(size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }
    static func meta() -> Font {
        .system(size: 12, weight: .regular)
    }

    // MARK: Helpers
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(UIColor(rgb: rgb))
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
    }
}

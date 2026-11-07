import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Color tokens (DESIGN.md §3.1). Defined in code instead of an asset catalog so `swift test`
// still builds the package on macOS. Views use `Color.orbit.*` only — never hex.
public extension Color {
    static let orbit = OrbitColors()
}

public struct OrbitColors: Sendable {
    /// Button fill only, always with `onPrimary` content. Never text/lines on light backgrounds.
    public let primary = Color(hex: 0xCEF35C)
    public let onPrimary = Color.black
    /// Big numbers, rings, checks, active tab, links. Green in light, lime in dark.
    public let accent = Color(light: Color(hex: 0x135B42), dark: Color(hex: 0xCEF35C))
    public let onAccent = Color(light: .white, dark: .black)
    public let accentSoft = Color(light: Color(hex: 0xE3EFEA), dark: Color(hex: 0xCEF35C).opacity(0.14))
    public let track = Color(light: Color(hex: 0xDCEAE4), dark: Color(hex: 0x3A3A3C))
    public let heroTop = Color(hex: 0x1A7353)
    public let heroBottom = Color(hex: 0x0C3D2B)
    public let ink = Color(hex: 0x0F0F0F)
    public let card = Color(light: .white, dark: Color(hex: 0x1C1C1E))
    public let textSecondary = Color(light: Color(hex: 0x6C6C70), dark: Color(hex: 0xAEAEB2))
    public let iconTile = Color(light: Color(hex: 0xF2F2F7), dark: Color(hex: 0x2C2C2E))
    public let iconTint = Color(light: Color(hex: 0x3A3A3C), dark: Color(hex: 0xEBEBF5))
    #if canImport(UIKit)
    public let bg = Color(light: Color(uiColor: .systemGroupedBackground), dark: .black)
    #else
    public let bg = Color.black
    #endif

    /// Heatmap levels 0–4.
    public func heat(_ level: Int) -> Color {
        switch level {
        case ..<1: .white.opacity(0.10)
        case 1: Color(hex: 0xCEF35C).opacity(0.28)
        case 2: Color(hex: 0xCEF35C).opacity(0.52)
        case 3: Color(hex: 0xCEF35C).opacity(0.78)
        default: Color(hex: 0xCEF35C)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double(hex >> 16 & 0xFF) / 255,
            green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        self = light
        #endif
    }
}

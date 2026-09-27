import SwiftUI
import AppKit

/// Design tokens for USB Drive Doctor.
///
/// Domain: this app is a diagnostic instrument for a physically real,
/// sometimes-dying piece of hardware - closer to a bedside vitals monitor
/// than a settings panel. Everything here is built from that world:
/// a steady phosphor-green trace means the signal is healthy, amber means
/// "worth watching," red is reserved strictly for an active fault - never
/// decoration. The permanent "read-only" guarantee is the app's equivalent
/// of "do no harm": a calm, structural fact, not a warning banner.
enum Theme {

    // MARK: - Surfaces (elevation scale - whisper-quiet steps, not jumps)

    static let canvas = Color.dynamic(light: "#F4F5F7", dark: "#0B0F14")
    static let surface1 = Color.dynamic(light: "#FFFFFF", dark: "#12171D")   // cards
    static let surface2 = Color.dynamic(light: "#FFFFFF", dark: "#1A2129")   // popovers, nested rows
    static let inset = Color.dynamic(light: "#EFF1F3", dark: "#0F1319")     // recessed / input-like surfaces

    // MARK: - Borders (hairline, never a hard divider)

    static let hairline = Color.dynamic(light: "#00000010", dark: "#FFFFFF12")
    static let hairlineSoft = Color.dynamic(light: "#00000008", dark: "#FFFFFF0A")
    static let hairlineEmphasis = Color.dynamic(light: "#00000022", dark: "#FFFFFF22")

    // MARK: - Text hierarchy

    static let textPrimary = Color.dynamic(light: "#14171A", dark: "#EDEFF2")
    static let textSecondary = Color.dynamic(light: "#52585F", dark: "#A6AEB8")
    static let textTertiary = Color.dynamic(light: "#7A828A", dark: "#6B7480")
    static let textMuted = Color.dynamic(light: "#A0A6AD", dark: "#4A515B")

    // MARK: - Semantic (motivated - each maps to one real, specific meaning)

    /// The signal is steady: nothing concerning seen recently.
    static let signalHealthy = Color.dynamic(light: "#1F9D5C", dark: "#3DDC84")
    /// Worth watching - a tip, or a device on a link mode known to be fragile.
    /// Deliberately NOT the same hue family as canvas/steel, and deliberately
    /// NOT alarm-red - this is advisory, not a fault.
    static let advisory = Color.dynamic(light: "#A9781E", dark: "#D9A544")
    /// An actual, currently-true fault: a disconnect, an aborted transfer,
    /// a failed mount. Reserved exclusively for real faults - never for
    /// static disclaimer text, never for describing a filter, never decorative.
    static let critical = Color.dynamic(light: "#C4292E", dark: "#E5484D")
    /// Structural accent - the instrument-panel blue used for icons, focus,
    /// and the brand mark. Not a status color.
    static let accent = Color.dynamic(light: "#3E6E96", dark: "#5B8DBE")

    // MARK: - Radii & spacing

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 10
    static let radiusLarge: CGFloat = 14

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
}

// MARK: - Typography

extension Font {
    /// Disk / volume name - the thing a human is scanning for first.
    static let vitalDisplay = Font.system(size: 15, weight: .semibold, design: .default)
    /// Field labels ("SIZE", "PROTOCOL") - small, spaced, quiet. Instrument-
    /// panel labeling, not a sentence.
    static let vitalLabel = Font.system(size: 10.5, weight: .medium, design: .default)
    /// Field values - tabular monospaced so a column of numbers actually lines up.
    static let vitalData = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// IDs, paths, secondary metadata.
    static let vitalMeta = Font.system(size: 10.5, weight: .regular, design: .default)
    /// Live log lines.
    static let logLine = Font.system(size: 11.5, weight: .regular, design: .monospaced)
    static let logTimestamp = Font.system(size: 10, weight: .regular, design: .monospaced)
}

extension Text {
    /// Small-caps-feeling uppercase label with the tracking a physical
    /// instrument panel would use - never rely on size alone for hierarchy.
    func vitalLabelStyle() -> Text {
        self.font(.vitalLabel)
            .tracking(0.6)
    }
}

// MARK: - Color(hex:) + light/dark dynamic helper

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var a: UInt64 = 0xFF
        var r: UInt64 = 0
        var g: UInt64 = 0
        var b: UInt64 = 0
        if s.count == 8 {
            let av = s.suffix(2)
            s = String(s.dropLast(2))
            a = UInt64(av, radix: 16) ?? 0xFF
        }
        var hexValue: UInt64 = 0
        Scanner(string: s).scanHexInt64(&hexValue)
        r = (hexValue >> 16) & 0xFF
        g = (hexValue >> 8) & 0xFF
        b = hexValue & 0xFF
        self = Color(.sRGB,
                      red: Double(r) / 255,
                      green: Double(g) / 255,
                      blue: Double(b) / 255,
                      opacity: Double(a) / 255)
    }

    /// A color that resolves differently in light vs dark mode, without
    /// needing an asset catalog (this is a pure SwiftPM app).
    static func dynamic(light: String, dark: String) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        }))
    }
}

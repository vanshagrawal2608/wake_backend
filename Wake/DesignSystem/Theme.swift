import SwiftUI

/// The night→dawn design system. Intensity is expressed as warmth:
/// gentle stages glow cool indigo, aggressive stages heat to dawn coral.
enum Theme {
    // Grounds — deep night with a warm maroon bias, never pure black.
    static let night0 = Color(hex: 0x0A0406)
    static let night1 = Color(hex: 0x0E0608)
    static let card    = Color(hex: 0x1C0E12)
    static let card2   = Color(hex: 0x22111A)

    // Text — warm off-white.
    static let text  = Color(hex: 0xF4EAEC)
    static let muted = Color(hex: 0xA78A90)
    static let faint = Color(hex: 0x6E5157)
    static let hair  = Color.white.opacity(0.06)

    // Intensity ramp — the accent. 0 = gentle/deep maroon → 1 = emergency/ember.
    static let i0 = Color(hex: 0x7E2A38)   // maroon
    static let i1 = Color(hex: 0xA62F42)   // wine crimson
    static let i2 = Color(hex: 0xD03B44)   // blood red
    static let i3 = Color(hex: 0xF2603F)   // ember

    static let accent = i2
    static let good   = Color(hex: 0xE6B15E)   // warm gold, positive state

    /// Interpolated colour for an intensity 0…1 — the heart of the system.
    static func intensity(_ t: Double) -> Color {
        let stops: [(Double, Color)] = [(0, i0), (0.38, i1), (0.70, i2), (1, i3)]
        let x = min(max(t, 0), 1)
        for i in 0..<(stops.count - 1) {
            let (a, ca) = stops[i], (b, cb) = stops[i + 1]
            if x <= b {
                let f = (x - a) / (b - a)
                return ca.mix(cb, f)
            }
        }
        return i3
    }

    static let corner: CGFloat = 26
}

// MARK: - Reusable surfaces

/// The rounded card used everywhere, with the subtle top-lit gradient.
struct WakeCard<Content: View>: View {
    @ViewBuilder var content: Content
    var padding: CGFloat = 20
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Theme.card, Theme.card2],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hair))
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// App-wide night ground with warm ember glow rising from the bottom —
/// mirrors the mockup so every screen sits in the same world.
struct NightBackground: View {
    var body: some View {
        ZStack {
            Theme.night0
            RadialGradient(colors: [Theme.i3.opacity(0.20), .clear],
                           center: .init(x: 0.5, y: 1.15), startRadius: 0, endRadius: 460)
            RadialGradient(colors: [Theme.i0.opacity(0.22), .clear],
                           center: .init(x: 0.5, y: -0.1), startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// Tracked-out uppercase micro-label.
struct MicroLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(Theme.faint)
    }
}

// MARK: - Colour helpers

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    /// Linear mix in sRGB — good enough for our gradient stops.
    func mix(_ other: Color, _ t: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let f = CGFloat(t)
        return Color(.sRGB,
                     red: ar + (br - ar) * f,
                     green: ag + (bg - ag) * f,
                     blue: ab + (bb - ab) * f)
    }
}

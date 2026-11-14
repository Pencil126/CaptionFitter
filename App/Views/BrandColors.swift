import AppKit
import SwiftUI

/// Colours taken from the app icon.
extension Color {
    /// The icon's navy background.
    static let brandNavy = Color(.sRGB, red: 0x15 / 255.0, green: 0x17 / 255.0, blue: 0x2B / 255.0)

    /// The icon's amber. For fills only: it is too pale for glyphs or text on a light background.
    static let brandAmber = Color(.sRGB, red: 1.0, green: 0xC5 / 255.0, blue: 0x3D / 255.0)

    /// Amber for glyphs drawn straight on the window background. Light mode gets a deeper
    /// shade because the icon's amber almost disappears on white.
    static let brandGlyph = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0xC5 / 255.0, blue: 0x3D / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xCC / 255.0, green: 0x8F / 255.0, blue: 0, alpha: 1)
    })
}

extension View {
    /// Tints a filled control (prominent button, slider, checkbox, segmented picker, progress
    /// bar) with the icon's amber; the system then picks a dark label that stays readable.
    ///
    /// This is applied per control rather than once at the window root on purpose: a root tint
    /// also recolours the labels of ordinary bordered buttons, which makes them unreadable in
    /// light mode.
    func brandTint() -> some View {
        tint(.brandAmber)
    }
}

/// The title of a button filled with `brandTint()`, drawn in the icon's navy.
///
/// The navy is only used while the button actually shows its amber fill. A disabled button, or
/// one in a window that is not active, loses the fill and turns grey; navy on that grey is
/// unreadable in dark mode, so the system's own label colour is left alone there.
struct BrandButtonLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appearsActive) private var appearsActive
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        if isEnabled && appearsActive {
            Text(title).foregroundStyle(Color.brandNavy)
        } else {
            Text(title)
        }
    }
}

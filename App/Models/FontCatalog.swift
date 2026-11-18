import AppKit
import CoreText

/// A font family as listed in the font picker.
struct FontFamilyInfo: Identifiable, Hashable, Sendable {
    enum Group: Int, CaseIterable, Sendable {
        case chinese, english, other

        var title: String {
            switch self {
            case .chinese: return String(localized: "Chinese Fonts")
            case .english: return String(localized: "English Fonts")
            case .other: return String(localized: "Other Fonts")
            }
        }
    }

    /// The family name used to load the font, e.g. "PingFang TC".
    let name: String
    /// The name in the user's language, e.g. "蘋方-繁".
    let displayName: String
    let group: Group
    /// False for symbol fonts and the like, whose own name would come out as boxes or pictures.
    let showsOwnName: Bool

    var id: String { name }

    func matches(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query) || displayName.localizedCaseInsensitiveContains(query)
    }
}

/// The fonts installed on this Mac, sorted into groups. Built once, in the background.
enum FontCatalog {
    private static let loading = Task.detached(priority: .userInitiated) { build() }

    static var families: [FontFamilyInfo] {
        get async { await loading.value }
    }

    /// Starts building the list so it is ready when the picker opens.
    static func preload() {
        _ = loading
    }

    static func displayName(for family: String) -> String {
        NSFontManager.shared.localizedName(forFamily: family, face: nil)
    }

    /// The common weight names in the user's language, followed by the font's own name;
    /// anything else is shown as the font calls it.
    static func weightLabel(_ styleName: String) -> String {
        // Fonts name their weights in English, so an English interface shows them as they are.
        guard Bundle.main.preferredLocalizations.first != "en" else { return styleName }
        let key = styleName.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        let ultraLight = LocalizedStringResource("Ultralight", comment: "Font weight")
        let regular = LocalizedStringResource("Regular", comment: "Font weight")
        let semibold = LocalizedStringResource("Semibold", comment: "Font weight")
        let heavy = LocalizedStringResource("Heavy", comment: "Font weight")
        let names: [String: LocalizedStringResource] = [
            "ultralight": ultraLight, "extralight": ultraLight,
            "thin": LocalizedStringResource("Thin", comment: "Font weight"),
            "light": LocalizedStringResource("Light", comment: "Font weight"),
            "regular": regular, "roman": regular, "book": regular, "normal": regular, "plain": regular,
            "medium": LocalizedStringResource("Medium", comment: "Font weight"),
            "semibold": semibold, "demibold": semibold, "demi": semibold,
            "bold": LocalizedStringResource("Bold", comment: "Font weight"),
            "extrabold": heavy, "heavy": heavy,
            "black": LocalizedStringResource("Black", comment: "Font weight"),
        ]
        guard let name = names[key] else { return styleName }
        return String(localized: "\(String(localized: name)) (\(styleName))", comment: "Font weight: the translated name, then the font's own name")
    }

    /// Languages written in scripts of their own. A font made for one of these usually has
    /// Latin letters too, but it is not what someone looking for an English font wants.
    private static let otherScripts: Set<String> = [
        "ja", "ko", "th", "lo", "km", "my", "bn", "hi", "mr", "ne", "sa", "ta", "te", "kn", "ml",
        "gu", "pa", "or", "si", "bo", "dz", "am", "ti", "chr", "iu",
    ]

    private static func build() -> [FontFamilyInfo] {
        let names = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        return names.filter { !$0.hasPrefix(".") }.map { name in
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: name] as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            let languages = (CTFontCopySupportedLanguages(font) as? [String]) ?? []
            let displayName = (CTFontCopyLocalizedName(font, kCTFontFamilyNameKey, nil) as String?) ?? name

            let group: FontFamilyInfo.Group
            if languages.contains(where: { $0.hasPrefix("zh") }) {
                group = .chinese
            } else if languages.contains("en"), otherScripts.isDisjoint(with: languages) {
                group = .english
            } else {
                group = .other
            }

            let characters = Array(displayName.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            let showsOwnName = CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
            return FontFamilyInfo(name: name, displayName: displayName, group: group, showsOwnName: showsOwnName)
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

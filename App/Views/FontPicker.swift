import SwiftUI

/// A searchable list of the installed fonts, grouped, each shown in its own typeface.
/// Choosing a font applies it at once and keeps the list open, so several can be tried
/// against the video.
struct FontPicker: View {
    @Binding var selection: String
    @AppStorage("recentFonts") private var recentRaw = ""
    @State private var families: [FontFamilyInfo] = []
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private static let recentLimit = 5

    var body: some View {
        VStack(spacing: 0) {
            TextField("搜尋字型", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(10)
            Divider()
            if families.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sections.isEmpty {
                Text("找不到符合「\(query)」的字型")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.fonts) { font in
                                row(font)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 300, height: 440)
        .task {
            families = await FontCatalog.families
            searchFocused = true
        }
        .onDisappear { remember(selection) }
    }

    private func row(_ font: FontFamilyInfo) -> some View {
        Button {
            selection = font.name
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(font.displayName)
                        .font(font.showsOwnName ? .custom(font.name, size: 15) : .system(size: 15))
                        .lineLimit(1)
                    if font.displayName != font.name {
                        Text(font.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if font.name == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.brandGlyph)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Recently used fonts first (when not searching), then the groups; empty ones are left out.
    private var sections: [(title: String, fonts: [FontFamilyInfo])] {
        let term = query.trimmingCharacters(in: .whitespaces)
        var sections: [(title: String, fonts: [FontFamilyInfo])] = []
        if term.isEmpty {
            let recent = recentNames.compactMap { name in families.first { $0.name == name } }
            if !recent.isEmpty { sections.append(("最近使用", recent)) }
        }
        let shown = term.isEmpty ? families : families.filter { $0.matches(term) }
        for group in FontFamilyInfo.Group.allCases {
            let fonts = shown.filter { $0.group == group }
            if !fonts.isEmpty { sections.append((group.title, fonts)) }
        }
        return sections
    }

    private var recentNames: [String] {
        recentRaw.split(separator: "\n").map(String.init)
    }

    private func remember(_ name: String) {
        var names = recentNames.filter { $0 != name }
        names.insert(name, at: 0)
        recentRaw = names.prefix(Self.recentLimit).joined(separator: "\n")
    }
}

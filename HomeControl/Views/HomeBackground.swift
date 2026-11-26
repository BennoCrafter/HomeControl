import PhotosUI
import SQLiteData
import SwiftUI

enum BackgroundPreset: String, CaseIterable, Identifiable {
    case plain, aurora, sunset, ocean, forest, midnight

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .plain: "Plain"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .midnight: "Midnight"
        }
    }

    var colors: [Color] {
        switch self {
        case .plain: [Color(.systemGroupedBackground)]
        case .aurora: [.indigo, .purple, .teal, .blue, .mint, .indigo, .purple, .cyan, .blue]
        case .sunset: [.orange, .pink, .purple, .red, .orange, .pink, .yellow, .orange, .red]
        case .ocean: [.blue, .cyan, .teal, .indigo, .blue, .cyan, .teal, .blue, .indigo]
        case .forest: [.green, .mint, .teal, .green, .brown, .green, .mint, .green, .teal]
        case .midnight: [.black, .indigo, .black, .purple, .black, .indigo, .black, .blue, .black]
        }
    }

    @ViewBuilder
    var view: some View {
        if self == .plain {
            Color(.systemGroupedBackground)
        } else {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.6, 0.4], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: colors)
            .overlay(Color(.systemBackground).opacity(0.35)) // keeps text readable in light and dark
        }
    }
}

extension EnvironmentValues {
    /// The current home's look.
    @Entry var appearance = Appearance(id: "")
}

/// Behind the dashboard and the rooms: the home's preset or photo.
struct HomeBackground: View {
    @Environment(\.appearance) private var appearance

    var body: some View {
        Group {
            if appearance.background == "photo", let data = appearance.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color(.systemBackground).opacity(0.3))
            } else {
                (BackgroundPreset(rawValue: appearance.background) ?? .aurora).view
            }
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.5), value: appearance)
    }
}

/// Settings for the home's look: a preset or a photo, and how see-through the tiles are.
struct AppearanceSection: View {
    let homeID: String
    @Environment(\.appearance) private var appearance
    @State private var photo: PhotosPickerItem?
    @State private var opacity: Double?

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BackgroundPreset.allCases) { preset in
                        swatch(preset.title, selected: appearance.background == preset.rawValue) {
                            preset.view
                        } action: {
                            save { $0.background = preset.rawValue }
                        }
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Swatch(title: "Photo", selected: appearance.background == "photo", content: photoPreview)
                    }
                    .buttonStyle(PressScale())
                }
                .padding(.vertical, 6)
            }
            VStack(alignment: .leading) {
                LabeledContent("Tiles", value: (opacity ?? appearance.tileOpacity).formatted(.percent.precision(.fractionLength(0))))
                Slider(value: Binding(get: { opacity ?? appearance.tileOpacity }, set: { opacity = $0 }), in: 0.1 ... 1) { editing in
                    if !editing, let opacity {
                        save { $0.tileOpacity = opacity }
                        self.opacity = nil
                    }
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("The background of this home, and how solid the tiles are on top of it.")
        }
        .sensoryFeedback(.selection, trigger: appearance.background)
        .onChange(of: photo) {
            Task {
                guard let data = try? await photo?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                // Stored downscaled: a 48 MP photo would bloat the database for a blurred backdrop.
                let small = image.preparingThumbnail(of: CGSize(width: 1600, height: 1600 * image.size.height / max(image.size.width, 1)))
                save {
                    $0.photo = small?.jpegData(compressionQuality: 0.8)
                    $0.background = "photo"
                }
            }
        }
    }

    private func swatch(_ title: LocalizedStringKey, selected: Bool, @ViewBuilder content: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) { Swatch(title: title, selected: selected, content: content()) }
            .buttonStyle(PressScale())
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let data = appearance.photo, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color(.tertiarySystemFill).overlay { Image(systemName: "photo.badge.plus").font(.title2) }
        }
    }

    private func save(_ change: (inout Appearance) -> Void) {
        var new = appearance
        new.id = homeID
        change(&new)
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in try Appearance.upsert { new }.execute(db) }
        } catch {
            logger.error("Saving the appearance failed: \(error)")
        }
    }
}

private struct Swatch<Content: View>: View {
    let title: LocalizedStringKey
    let selected: Bool
    let content: Content

    var body: some View {
        VStack(spacing: 6) {
            content
                .frame(width: 64, height: 96)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .scaleEffect(selected ? 1.05 : 1)
                .animation(.spring(duration: 0.3, bounce: 0.5), value: selected)
            Text(title).font(.caption).foregroundStyle(selected ? .primary : .secondary)
        }
    }
}

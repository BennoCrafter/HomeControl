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

extension Appearance {
    var gradient: GradientStyle {
        get { gradientJSON.flatMap { try? JSONDecoder().decode(GradientStyle.self, from: $0) } ?? GradientStyle() }
        set { gradientJSON = try? JSONEncoder().encode(newValue) }
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
            if appearance.background == "custom" {
                GrainyGradient(style: appearance.gradient)
                    .overlay(Color(.systemBackground).opacity(0.15))
            } else if appearance.background == "photo", let data = appearance.photo, let image = UIImage(data: data) {
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

/// Draws a background at the screen's size, then shrinks it into the frame: grain, blur and dimming look as they will behind the home.
struct ScreenPreview<Content: View>: View {
    @ViewBuilder let content: Content

    static var screen: CGSize {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size ?? CGSize(width: 402, height: 874)
    }

    var body: some View {
        GeometryReader { geometry in
            let screen = Self.screen
            let scale = max(geometry.size.width / screen.width, geometry.size.height / screen.height)
            content
                .frame(width: screen.width, height: screen.height)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }
}

/// Settings for the home's look: a preset or a photo, and how see-through the tiles are.
struct AppearanceSection: View {
    let homeID: String
    @Environment(\.appearance) private var appearance
    @State private var photo: PhotosPickerItem?
    /// A picked photo waiting in the editor.
    @State private var editingPhoto: UIImage?
    @State private var opacity: Double?
    @State private var editingGradient = false

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BackgroundPreset.allCases) { preset in
                        swatch(preset.title, selected: appearance.background == preset.rawValue) {
                            ScreenPreview { HomeBackground().environment(\.appearance, looking { $0.background = preset.rawValue }) }
                        } action: {
                            save { $0.background = preset.rawValue }
                        }
                    }
                    swatch("Custom", selected: appearance.background == "custom") {
                        ScreenPreview { HomeBackground().environment(\.appearance, looking { $0.background = "custom" }) }
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(5)
                                    .background(.black.opacity(0.3), in: .circle)
                                    .padding(4)
                            }
                    } action: {
                        editingGradient = true
                    }
                    PhotosPicker(selection: $photo, matching: .images) {
                        Swatch(title: "Photo", selected: appearance.background == "photo", content: photoPreview)
                    }
                    .buttonStyle(PressScale())
                    .contextMenu {
                        if let data = appearance.photo, let image = UIImage(data: data) {
                            Button("Edit Photo", systemImage: "crop") { editingPhoto = image }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            // On the row, not the Section: a Section hands its modifiers to every row, and two sheets fight.
            .sensoryFeedback(.selection, trigger: appearance.background)
            .sheet(isPresented: $editingGradient) {
                GradientEditor(style: appearance.gradient) { style in
                    save {
                        $0.gradient = style
                        $0.background = "custom"
                    }
                }
            }
            .onChange(of: photo) {
                guard let photo else { return }
                Task {
                    self.photo = nil // so picking the same photo again opens the editor again
                    guard let data = try? await photo.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    // Downscaled: a 48 MP photo would slow the editor and bloat the database for a backdrop.
                    let side = 2000 / max(image.size.width, image.size.height, 1)
                    editingPhoto = side < 1 ? image.preparingThumbnail(of: CGSize(width: image.size.width * side, height: image.size.height * side)) : image
                }
            }
            .sheet(isPresented: Binding(get: { editingPhoto != nil }, set: { if !$0 { editingPhoto = nil } })) {
                if let editingPhoto {
                    PhotoEditor(image: editingPhoto) { edited in
                        save {
                            $0.photo = edited.jpegData(compressionQuality: 0.8)
                            $0.background = "photo"
                        }
                    }
                }
            }
            VStack(alignment: .leading) {
                LabeledContent("Opacity", value: (opacity ?? appearance.tileOpacity).formatted(.percent.precision(.fractionLength(0))))
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
    }

    private func swatch(_ title: LocalizedStringKey, selected: Bool, @ViewBuilder content: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) { Swatch(title: title, selected: selected, content: content()) }
            .buttonStyle(PressScale())
    }

    /// The current look with one change, for a swatch.
    private func looking(_ change: (inout Appearance) -> Void) -> Appearance {
        var look = appearance
        change(&look)
        return look
    }

    @ViewBuilder
    private var photoPreview: some View {
        if appearance.photo != nil {
            ScreenPreview { HomeBackground().environment(\.appearance, looking { $0.background = "photo" }) }
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
            HomeStore.shared.report(error, saving: "the appearance")
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

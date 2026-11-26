import AppIntents
import SwiftUI
import WidgetKit

@main
struct HomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        AccessoryWidget()
        RoomWidget()
        StatusWidget()
        CameraWidget()
        AccessoryControl()
    }
}

struct HomeEntry: TimelineEntry {
    var date = Date.now
    var homeName = "Home"
    var devices: [Device] = []
    /// The accessory a widget was set up with.
    var selected: String?

    static let placeholder = HomeEntry(homeName: "Home", devices: [
        Device(id: UUID(), name: "Ceiling Light", accessoryName: "", room: "Living Room", kind: .light, isOn: true, value: 0.8),
        Device(id: UUID(), name: "Front Door", accessoryName: "", room: "Hallway", kind: .lock, isOn: true, currentState: 1),
        Device(id: UUID(), name: "Shutters", accessoryName: "", room: "Living Room", kind: .blinds, value: 0.6),
        Device(id: UUID(), name: "Apple TV", accessoryName: "", room: "Living Room", kind: .plug),
    ])

    static func current() -> HomeEntry {
        guard let snapshot = WidgetData.snapshot() else { return HomeEntry() }
        return HomeEntry(homeName: snapshot.homeName, devices: snapshot.devices)
    }
}

// MARK: - Accessory

struct SelectDeviceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Accessory"
    @Parameter(title: "Accessory") var device: DeviceEntity?
}

struct DeviceProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> HomeEntry { .placeholder }
    func snapshot(for intent: SelectDeviceIntent, in context: Context) async -> HomeEntry {
        context.isPreview ? .placeholder : entry(intent)
    }

    // The app reloads widgets whenever the home changes; no schedule needed.
    func timeline(for intent: SelectDeviceIntent, in _: Context) async -> Timeline<HomeEntry> {
        Timeline(entries: [entry(intent)], policy: .never)
    }

    private func entry(_ intent: SelectDeviceIntent) -> HomeEntry {
        var entry = HomeEntry.current()
        entry.selected = intent.device?.id
        return entry
    }
}

/// One accessory; tap to toggle. Small ones also appear on CarPlay.
struct AccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Accessory", intent: SelectDeviceIntent.self, provider: DeviceProvider()) { entry in
            AccessoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Accessory")
        .description("Shows an accessory and switches it with a tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

private struct AccessoryWidgetView: View {
    let entry: HomeEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        // The configured accessory, or the first one before the widget was set up.
        let device = entry.devices.first { $0.id.uuidString == entry.selected } ?? entry.devices.first { $0.kind.isControllable }
        Group {
            if let device {
                switch family {
                case .accessoryCircular:
                    Button(intent: ToggleDeviceIntent(id: device.id)) {
                        ZStack {
                            AccessoryWidgetBackground()
                            Image(systemName: device.icon).font(.title2)
                        }
                    }
                    .buttonStyle(.plain)
                case .accessoryRectangular:
                    Button(intent: ToggleDeviceIntent(id: device.id)) {
                        HStack {
                            Image(systemName: device.icon).font(.title2)
                            VStack(alignment: .leading) {
                                Text(device.name).font(.headline).lineLimit(1).minimumScaleFactor(0.4)
                                Text(device.status).font(.caption).lineLimit(1).minimumScaleFactor(0.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                default:
                    small(device)
                }
            } else {
                ContentUnavailableView("Open HomeControl", systemImage: "house")
            }
        }
        .containerBackground(for: .widget) {
            if let device, device.isActive {
                LinearGradient(colors: [device.kind.tint.opacity(0.35), device.kind.tint.opacity(0.12)], startPoint: .top, endPoint: .bottom)
            } else {
                Color(.secondarySystemBackground)
            }
        }
    }

    /// The whole widget is the switch.
    private func small(_ device: Device) -> some View {
        Button(intent: ToggleDeviceIntent(id: device.id)) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: device.icon)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(device.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 56, height: 56)
                    .background(device.isActive ? AnyShapeStyle(device.kind.tint.gradient) : AnyShapeStyle(.quaternary), in: .circle)
                    .contentTransition(.symbolEffect(.replace))
                Spacer(minLength: 0)
                Text(device.name).font(.headline).lineLimit(1).minimumScaleFactor(0.4)
                Text(device.status).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .invalidatableContent()
    }
}

// MARK: - Room

struct SelectRoomIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Room"
    @Parameter(title: "Room") var room: RoomEntity?
}

struct RoomProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> RoomEntry { RoomEntry(room: "Living Room", home: .placeholder) }

    func snapshot(for intent: SelectRoomIntent, in context: Context) async -> RoomEntry {
        context.isPreview ? placeholder(in: context) : entry(for: intent)
    }

    func timeline(for intent: SelectRoomIntent, in _: Context) async -> Timeline<RoomEntry> {
        Timeline(entries: [entry(for: intent)], policy: .never)
    }

    private func entry(for intent: SelectRoomIntent) -> RoomEntry {
        let home = HomeEntry.current()
        return RoomEntry(room: intent.room?.id ?? home.devices.first?.room ?? "", home: home)
    }
}

struct RoomEntry: TimelineEntry {
    var date = Date.now
    var room: String
    var home: HomeEntry
}

/// A room with a toggle for each of its first four accessories.
struct RoomWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Room", intent: SelectRoomIntent.self, provider: RoomProvider()) { entry in
            RoomWidgetView(entry: entry)
                .containerBackground(Color(.secondarySystemBackground), for: .widget)
        }
        .configurationDisplayName("Room")
        .description("A room's accessories, each a tap away.")
        .supportedFamilies([.systemMedium])
    }
}

private struct RoomWidgetView: View {
    let entry: RoomEntry

    var body: some View {
        let devices = entry.home.devices.filter { $0.room == entry.room && $0.kind.isControllable && $0.confirmationAction == nil }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.room).font(.headline)
                Spacer()
                Text("\(devices.count(where: \.isActive)) on").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(devices.prefix(4)) { device in
                    Button(intent: ToggleDeviceIntent(id: device.id)) {
                        VStack(spacing: 6) {
                            Image(systemName: device.icon)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(device.isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                                .frame(width: 48, height: 48)
                                .background(device.isActive ? AnyShapeStyle(device.kind.tint.gradient) : AnyShapeStyle(.quaternary), in: .circle)
                            Text(device.name).font(.caption2).lineLimit(1).minimumScaleFactor(0.4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Status

struct StatusProvider: TimelineProvider {
    func placeholder(in _: Context) -> HomeEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) { completion(context.isPreview ? .placeholder : .current()) }
    func getTimeline(in _: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) { completion(Timeline(entries: [.current()], policy: .never)) }
}

/// What's on, open or unlocked, and how warm it is.
struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Status", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(Color(.secondarySystemBackground), for: .widget)
        }
        .configurationDisplayName("Home Status")
        .description("Lights on, doors open, locks unlocked and the temperature.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct StatusWidgetView: View {
    let entry: HomeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let lights = entry.devices.count { $0.kind == .light && $0.isOn }
        let open = entry.devices.count { ($0.kind == .contact && $0.isContactOpen) || ($0.kind == .garage && !$0.isOn) }
        let unlocked = entry.devices.count { $0.kind == .lock && !$0.isOn }
        let temperatures = entry.devices.compactMap { $0.kind == .thermostat ? $0.currentValue : nil }
        let temperature = temperatures.isEmpty ? "–" : Device.celsius(temperatures.reduce(0, +) / Double(temperatures.count))
        let rows: [(String, String, Color, Bool)] = [
            ("lightbulb.fill", "\(lights) on", .yellow, lights > 0),
            ("door.left.hand.open", "\(open) open", .mint, open > 0),
            ("lock.open.fill", unlocked == 0 ? String(localized: "Locked") : "\(unlocked) unlocked", .red, unlocked > 0),
            ("thermometer.medium", temperature, .orange, false),
        ]
        if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Text(entry.homeName).font(.headline)
                Text("\(lights) on · \(open) open · \(temperature)").font(.caption)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.homeName).font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: family == .systemMedium ? 2 : 1), spacing: 6) {
                    ForEach(rows.indices, id: \.self) { index in
                        let (icon, text, tint, alert) = rows[index]
                        Label {
                            Text(text).font(.subheadline.weight(.semibold)).lineLimit(1)
                        } icon: {
                            Image(systemName: icon).foregroundStyle(alert ? tint : .secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Control Center

struct ControlDeviceIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Accessory"
    @Parameter(title: "Accessory") var device: DeviceEntity?
}

/// A toggle in Control Center and on the Lock Screen.
struct AccessoryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "AccessoryControl", intent: ControlDeviceIntent.self) { configuration in
            let device = configuration.device.flatMap { entity in WidgetData.snapshot()?.devices.first { $0.id.uuidString == entity.id } }
            ControlWidgetToggle(isOn: device?.isActive ?? false, action: setIntent(configuration.device)) {
                Label(device?.name ?? String(localized: "Accessory"), systemImage: device?.icon ?? "house")
            } valueLabel: { isOn in
                Text(isOn ? "On" : "Off")
            }
            .tint(device?.kind.tint ?? .yellow)
        }
        .displayName("Accessory")
        .description("Switch an accessory from Control Center.")
    }

    private func setIntent(_ device: DeviceEntity?) -> SetDeviceIntent {
        var intent = SetDeviceIntent()
        intent.device = device
        return intent
    }
}

// MARK: - Camera

enum WidgetLink {
    static func item(_ id: UUID) -> URL { URL(string: "homecontrol://item/\(id.uuidString)")! }
    static func room(_ name: String) -> URL { URL(string: "homecontrol://room")!.appending(path: name) }
}

struct CameraEntity: AppEntity {
    let id: String
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Camera"
    static let defaultQuery = CameraQuery()

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct CameraQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [CameraEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor func suggestedEntities() async throws -> [CameraEntity] {
        (WidgetData.snapshot()?.devices ?? []).filter { $0.kind == .camera }.map { CameraEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

struct SelectCameraIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Camera"
    @Parameter(title: "Camera") var camera: CameraEntity?
}

struct CameraEntry: TimelineEntry {
    var date = Date.now
    var name: String?
    var id: UUID?
    var image: UIImage?
    var takenAt: Date?
}

struct CameraProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> CameraEntry { CameraEntry(name: "Front Yard") }
    func snapshot(for intent: SelectCameraIntent, in context: Context) async -> CameraEntry {
        context.isPreview ? placeholder(in: context) : entry(intent)
    }

    // The app saves a new still while it's open; check back now and then.
    func timeline(for intent: SelectCameraIntent, in _: Context) async -> Timeline<CameraEntry> {
        Timeline(entries: [entry(intent)], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func entry(_ intent: SelectCameraIntent) -> CameraEntry {
        let cameras = (WidgetData.snapshot()?.devices ?? []).filter { $0.kind == .camera }
        guard let camera = cameras.first(where: { $0.id.uuidString == intent.camera?.id }) ?? cameras.first else { return CameraEntry() }
        let still = WidgetData.cameraImage(for: camera.id)
        return CameraEntry(name: camera.name, id: camera.id, image: still.flatMap { UIImage(data: $0.data) }, takenAt: still?.date)
    }
}

/// The camera's latest still, as the app last saw it; tap for the live picture.
struct CameraWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Camera", intent: SelectCameraIntent.self, provider: CameraProvider()) { entry in
            CameraWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    if let image = entry.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [.indigo, .blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
        }
        .configurationDisplayName("Camera")
        .description("The camera's latest picture. Opens the live view.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct CameraWidgetView: View {
    let entry: CameraEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            if entry.image == nil {
                Image(systemName: "web.camera.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text(entry.name ?? String(localized: "No Camera")).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                if let takenAt = entry.takenAt {
                    Text(takenAt, style: .relative)
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.35), in: .capsule)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .widgetURL(entry.id.map(WidgetLink.item))
    }
}

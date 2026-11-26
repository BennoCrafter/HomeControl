import SQLiteData
import SwiftUI

/// The home at a glance, arranged freely: cards on a grid, held to move, resized from the corner.
/// 4 columns on a phone, 8 on wider screens; the same layout fits itself to both.
struct DashboardView: View {
    /// The folder shown; nil is the dashboard itself.
    var folder: DeviceGroup?
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.itemPrefs) private var prefs
    @Environment(\.roomIcons) private var roomIcons
    @Namespace private var zoom
    @State private var openedFolder: DeviceGroup?
    @State private var openedCollection: DeviceGroup?
    @State private var editingCollection: DeviceGroup?
    @State private var addingCollection = false
    @State private var namingFolder = false
    @State private var newFolderName = ""
    @FetchAll private var allCards: [DashboardCard]
    @State private var isEditing = false
    @State private var drag: ActiveDrag?
    @State private var cardFrames: [Int: CGRect] = [:]
    @State private var selected: Device?
    @State private var openedRoom: String?
    @State private var confirmingReset = false
    /// The current grid width, for adding and removing outside of the layout pass.
    @State private var columns = 4

    private struct ActiveDrag: Equatable {
        var id: Int
        var handle: DragHandle
        var start: GridFrame
        var translation: CGSize
        /// Where it would land, snapped to the grid.
        var target: GridFrame
    }

    private var homeID: String { store.currentHomeID ?? "" }

    /// This screen size's layout, of the chosen profile.
    private var cards: [DashboardCard] {
        allCards.filter { $0.homeID == homeID && $0.columns == columns && $0.memberID == profiles.selected && $0.folderID == folder?.id && isValid($0) }
    }

    @State private var profiles = Profiles(homeID: "")
    @State private var namingProfile = false
    @State private var newProfileName = ""
    @State private var importing = false
    @State private var importError: String?

    /// Every card of the chosen person in this home, both screen sizes: what a shared file holds.
    private var shareableCards: [DashboardCard] {
        allCards.filter { $0.homeID == homeID && $0.memberID == profiles.selected && isValid($0) }
    }

    /// Cards of items or rooms that left the home are skipped, not deleted: they may come back.
    private func isValid(_ card: DashboardCard) -> Bool {
        switch card.kind {
        case .item, .camera: store.devices.contains { $0.id.uuidString == card.ref }
        case .room: store.rooms.contains(card.ref)
        case .status: true
        case .group, .collection, .folder: Int(card.ref).flatMap(store.group(id:)) != nil
        }
    }

    private func group(_ card: DashboardCard) -> DeviceGroup? {
        Int(card.ref).flatMap(store.group(id:))
    }

    /// A room's items, without those a group stands in for.
    private func items(in room: String) -> [Device] {
        let grouped = store.groupedIDs
        return store.devices.filter { $0.room == room && !grouped.contains($0.id) }
    }

    private func items(of group: DeviceGroup) -> [Device] {
        let all = store.devices + store.groupDevices
        return group.memberIDs.compactMap { id in all.first { $0.id == id } }
    }

    /// What a folder shows of the cards inside it.
    private func icon(for card: DashboardCard) -> (symbol: String, tint: Color) {
        let device = (store.devices + store.groupDevices).first { $0.id.uuidString == card.ref }
        switch card.kind {
        case .item, .camera: return (device?.icon(prefs) ?? "questionmark", device?.kind.tint ?? .gray)
        case .room: return (roomIcons[card.ref] ?? ContentView.icon(forRoom: card.ref), .accentColor)
        case .status: return ("gauge.with.dots.needle.67percent", .orange)
        case .group:
            let device = group(card).flatMap { group in store.groupDevices.first { $0.id == group.deviceID } }
            return (device?.icon ?? "square.stack.3d.up.fill", device?.kind.tint ?? .purple)
        case .collection: return (group(card)?.icon ?? "square.grid.2x2.fill", .pink)
        case .folder: return ("folder.fill", .blue)
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let columns = geometry.size.width < 600 ? 4 : 8
                let spacing: CGFloat = geometry.size.width < 600 ? 10 : 14
                let cell = max(1, (geometry.size.width - spacing * CGFloat(columns + 1)) / CGFloat(columns))
                // Rows a little shorter than wide: item cards read as tiles, not squares.
                // Never shorter than a tile: a phone on its side gets 8 narrow columns.
                let step = CGSize(width: cell + spacing, height: max(cell * 0.72, 76) + spacing)
                let frames = preview(columns: columns, step: step)
                let rows = (frames.values.map(\.maxY).max() ?? 0) + (isEditing ? 1 : 0)
                ScrollView {
                    canvas(frames: frames, columns: columns, step: step, spacing: spacing)
                        .frame(width: geometry.size.width - spacing * 2,
                               height: max(0, CGFloat(rows) * step.height - spacing),
                               alignment: .topLeading)
                        .padding(spacing)
                }
                .scrollDisabled(drag != nil)
                .overlay {
                    if cards.isEmpty, !store.devices.isEmpty {
                        ContentUnavailableView {
                            Label("Your Dashboard", systemImage: "square.grid.2x2")
                        } description: {
                            Text("Add rooms, items and a status card, then arrange them however you like.")
                        } actions: {
                            addMenu(columns: columns).buttonStyle(.borderedProminent)
                        }
                    } else if store.devices.isEmpty, let message = store.message {
                        ContentUnavailableView(message, systemImage: "house")
                    }
                }
                .toolbar { toolbar(columns: columns) }
                .task(id: "\(homeID)\(columns)\(profiles.selected)") {
                    self.columns = columns
                    if profiles.homeID != homeID { profiles = Profiles(homeID: homeID) }
                    seedIfNeeded(columns: columns)
                }
                #if DEBUG
                // Screenshots: `-edit YES` starts in edit mode, `-open <name>` opens an item or group, `-folder <name>` a folder.
                .task {
                    guard folder == nil else { return }
                    isEditing = UserDefaults.standard.bool(forKey: "edit")
                    let defaults = UserDefaults.standard
                    selected = (store.devices + store.groupDevices).first { $0.name == defaults.string(forKey: "open") }
                    openedFolder = store.groups(.folder).first { $0.name == defaults.string(forKey: "folder") }
                }
                #endif
            }
            .background(HomeBackground())
            .navigationTitle(folder?.name ?? store.homeName)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { DeviceDetailView(device: $0).environment(store) }
            .sheet(item: Binding(get: { openedRoom.map(IdentifiedString.init) }, set: { openedRoom = $0?.id })) { room in
                NavigationStack {
                    RoomView(title: room.id, devices: store.devices.filter { $0.room == room.id }, showRoom: false)
                        .toolbar { Button("Done") { openedRoom = nil } }
                }
                .environment(store)
            }
            .fullScreenCover(item: $openedFolder) { folder in
                DashboardView(folder: folder)
                    .environment(store)
                    .navigationTransition(.zoom(sourceID: folder.id, in: zoom))
            }
            .sheet(item: $openedCollection) { collection in
                NavigationStack {
                    RoomView(title: collection.name, devices: items(of: collection), showRoom: true)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { openedCollection = nil } } }
                }
                .environment(store)
            }
            .sheet(item: $editingCollection) { GroupEditor(kind: .collection, existing: $0).environment(store) }
            .sheet(isPresented: $addingCollection) {
                GroupEditor(kind: .collection) { id in add(.collection, ref: "\(id)", columns: columns) }.environment(store)
            }
            .alert("New Folder", isPresented: $namingFolder) {
                TextField("Name", text: $newFolderName)
                Button("Add") {
                    let name = newFolderName.trimmingCharacters(in: .whitespaces)
                    newFolderName = ""
                    if let id = Groups.save(DeviceGroup.Draft(homeID: homeID, kind: .folder, name: name.isEmpty ? String(localized: "Folder") : name)) {
                        add(.folder, ref: "\(id)", columns: columns)
                    }
                }
                Button("Cancel", role: .cancel) { newFolderName = "" }
            }
            .confirmationDialog("Reset the dashboard?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { reset() }
            }
        }
        .sensoryFeedback(trigger: drag != nil) { _, active in active ? .impact(weight: .medium) : .impact(weight: .light) }
        .sensoryFeedback(.selection, trigger: drag?.target)
        .sensoryFeedback(.impact(weight: .light), trigger: isEditing)
    }

    // MARK: - Grid

    private func canvas(frames: [Int: GridFrame], columns: Int, step: CGSize, spacing: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if isEditing {
                // The cells, faintly, so it's clear where a card can go.
                Canvas { context, size in
                    let rows = Int(size.height / step.height) + 1
                    let columns = Int((size.width + spacing) / step.width)
                    for row in 0 ..< rows {
                        for column in 0 ..< columns {
                            let rect = CGRect(x: CGFloat(column) * step.width, y: CGFloat(row) * step.height,
                                              width: step.width - spacing, height: step.height - spacing)
                            context.fill(Path(roundedRect: rect, cornerRadius: 12), with: .color(.primary.opacity(0.04)))
                        }
                    }
                }
                .transition(.opacity)
            }
            if let drag, let target = frames[drag.id] {
                // Where the card lands.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 20))
                    .frame(width: rect(target, step: step, spacing: spacing).width,
                           height: rect(target, step: step, spacing: spacing).height)
                    .position(x: rect(target, step: step, spacing: spacing).midX, y: rect(target, step: step, spacing: spacing).midY)
            }
            ForEach(cards) { card in
                if let frame = frames[card.id] {
                    let area = liveRect(card: card, target: frame, step: step, spacing: spacing)
                    cardView(card)
                        .frame(width: area.width, height: area.height)
                        .modifier(Jiggle(isOn: isEditing && drag?.id != card.id, seed: card.id))
                        .overlay(alignment: .topLeading) { if isEditing { removeButton(card) } }
                        .overlay(alignment: .bottomTrailing) { if isEditing { resizeGrip } }
                        .scaleEffect(drag?.id == card.id ? 1.04 : 1)
                        .shadow(color: .black.opacity(drag?.id == card.id ? 0.25 : 0), radius: 16, y: 8)
                        .zIndex(drag?.id == card.id ? 1 : 0)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { cardFrames[card.id] = $0 }
                        .gesture(dragGesture(card, columns: columns, step: step))
                        .position(x: area.midX, y: area.midY)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        // Only while arranging: otherwise a layout pass (launch, a sheet resizing the window) would send the cards flying.
        .animation(isEditing ? .spring(duration: 0.4, bounce: 0.25) : nil, value: frames)
        .animation(.spring(duration: 0.3), value: isEditing)
    }

    private func rect(_ frame: GridFrame, step: CGSize, spacing: CGFloat) -> CGRect {
        CGRect(x: CGFloat(frame.x) * step.width, y: CGFloat(frame.y) * step.height,
               width: CGFloat(frame.width) * step.width - spacing, height: CGFloat(frame.height) * step.height - spacing)
    }

    /// The dragged card follows the finger exactly; the rest sit on the grid.
    private func liveRect(card: DashboardCard, target: GridFrame, step: CGSize, spacing: CGFloat) -> CGRect {
        guard let drag, drag.id == card.id else { return rect(target, step: step, spacing: spacing) }
        let start = rect(drag.start, step: step, spacing: spacing)
        switch drag.handle {
        case .move:
            return start.offsetBy(dx: drag.translation.width, dy: drag.translation.height)
        case .resize:
            let min = card.kind.minSize
            return CGRect(x: start.minX, y: start.minY,
                          width: max(CGFloat(min.width) * step.width - spacing, start.width + drag.translation.width),
                          height: max(CGFloat(min.height) * step.height - spacing, start.height + drag.translation.height))
        }
    }

    private func committed(columns: Int) -> [Int: GridFrame] {
        DashboardEngine.fit(Dictionary(cards.map { ($0.id, $0.frame) }) { first, _ in first }, columns: columns)
    }

    private func preview(columns: Int, step _: CGSize) -> [Int: GridFrame] {
        let frames = committed(columns: columns)
        guard let drag else { return frames }
        return DashboardEngine.relayout(frames, moving: drag.id, to: drag.target, columns: columns)
    }

    private func desired(for drag: ActiveDrag, columns: Int, step: CGSize) -> GridFrame {
        let delta = DashboardEngine.cellDelta(for: drag.translation, step: step)
        var frame = drag.start
        switch drag.handle {
        case .move:
            frame.x += delta.dx
            frame.y += delta.dy
        case .resize:
            let kind = cards.first { $0.id == drag.id }?.kind ?? .item
            frame.width = min(columns - frame.x, max(kind.minSize.width, frame.width + delta.dx))
            frame.height = max(kind.minSize.height, frame.height + delta.dy)
        }
        return frame
    }

    private func dragGesture(_ card: DashboardCard, columns: Int, step: CGSize) -> HoldToDrag {
        HoldToDrag(isEnabled: isEditing) { location in
            guard let frame = cardFrames[card.id] else { return .move }
            return hypot(frame.maxX - location.x, frame.maxY - location.y) < 44 ? .resize : .move
        } onChanged: { handle, translation in
            let start = drag?.start ?? committed(columns: columns)[card.id] ?? card.frame
            var new = ActiveDrag(id: card.id, handle: handle, start: start, translation: translation, target: start)
            new.target = desired(for: new, columns: columns, step: step)
            drag = new
        } onEnded: { _, _ in
            if let drag {
                save(DashboardEngine.relayout(committed(columns: columns), moving: drag.id, to: drag.target, columns: columns))
            }
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { drag = nil }
        } onCancelled: {
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) { drag = nil }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func cardView(_ card: DashboardCard) -> some View {
        Group {
            switch card.kind {
            case .item:
                if let device = store.devices.first(where: { $0.id.uuidString == card.ref }) {
                    DeviceTile(device: device, showRoom: true) { selected = device }
                }
            case .room:
                RoomCard(title: card.ref, icon: roomIcons[card.ref] ?? ContentView.icon(forRoom: card.ref), items: items(in: card.ref),
                         large: card.height > 2 || card.width >= 4) { openedRoom = card.ref }
            case .status:
                StatusCard(compact: card.width < 4)
            case .camera:
                if let device = store.devices.first(where: { $0.id.uuidString == card.ref }) {
                    CameraCard(device: device)
                }
            case .group:
                // Small, it's a tile like any item; bigger, every member gets a button.
                if let group = group(card), let device = store.groupDevices.first(where: { $0.id == group.deviceID }) {
                    if card.height == 1 {
                        DeviceTile(device: device, showRoom: false) { selected = device }
                    } else {
                        RoomCard(title: group.name, icon: device.icon, items: store.members(of: group),
                                 large: card.height > 2 || card.width >= 4) { selected = device }
                    }
                }
            case .collection:
                if let collection = group(card) {
                    RoomCard(title: collection.name, icon: collection.icon ?? "square.grid.2x2.fill", items: items(of: collection),
                             large: card.height > 2 || card.width >= 4) { openedCollection = collection }
                        .contextMenu {
                            Button("Edit Collection…", systemImage: "pencil") { editingCollection = collection }
                        }
                }
            case .folder:
                if let folder = group(card) {
                    let inside = allCards.filter { $0.folderID == folder.id && $0.columns == columns && $0.memberID == profiles.selected && isValid($0) }
                    Button { openedFolder = folder } label: {
                        FolderCard(name: folder.name, icons: inside.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.map(icon(for:)))
                    }
                    .buttonStyle(PressScale(scale: 0.95))
                    .matchedTransitionSource(id: folder.id, in: zoom)
                    .sensoryFeedback(.impact(weight: .light), trigger: openedFolder != nil)
                }
            }
        }
        .allowsHitTesting(!isEditing)
        .overlay {
            if isEditing {
                // Catches the touches the content no longer takes, for the move and resize gesture.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.clear)
                    .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .contentShape(.rect(cornerRadius: 20))
            }
        }
    }

    private func removeButton(_ card: DashboardCard) -> some View {
        Button {
            withAnimation(.spring(duration: 0.35)) { remove(card) }
        } label: {
            Image(systemName: "minus")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.red.gradient, in: .circle)
                .shadow(radius: 3)
        }
        .buttonStyle(PressScale(scale: 0.8))
        .offset(x: -8, y: -8)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel("Remove")
    }

    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.accentColor.gradient, in: .circle)
            .shadow(radius: 3)
            .padding(6)
            .allowsHitTesting(false) // the card's gesture sees the corner and resizes
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(columns: Int) -> some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button("Reset", systemImage: "arrow.counterclockwise") { confirmingReset = true }
            }
            ToolbarItem(placement: .topBarTrailing) { addMenu(columns: columns) }
        }
        ToolbarItem(placement: .topBarLeading) {
            if folder != nil {
                Button("Close", systemImage: "chevron.down") { dismiss() }
            } else if !isEditing {
                profileMenu
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(isEditing ? "Done" : "Edit") {
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { isEditing.toggle() }
            }
            .fontWeight(isEditing ? .semibold : .regular)
            .disabled(store.devices.isEmpty)
        }
    }

    /// Everyone's own dashboard on a shared device. "Me" is this device's Home member.
    private var profileMenu: some View {
        Menu {
            Picker("Dashboard", selection: Binding(get: { profiles.selected }, set: { id in
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) { profiles.selected = id }
            })) {
                ForEach(profiles.all) { profile in
                    Label(profile.name, systemImage: profile.id.isEmpty ? "person.crop.circle.fill" : "person.crop.circle").tag(profile.id)
                }
            }
            Button("Add Person…", systemImage: "person.badge.plus") { namingProfile = true }
            Section {
                ShareLink(item: DashboardFile(cards: shareableCards, devices: store.devices, groups: store.allGroups),
                          preview: SharePreview("\(profiles.name(of: profiles.selected))'s Dashboard", image: Image(systemName: "square.grid.2x2")))
                Button("Import Dashboard…", systemImage: "square.and.arrow.down") { importing = true }
                let others = profiles.all.filter { $0.id != profiles.selected }
                if !others.isEmpty {
                    Menu("Copy From", systemImage: "doc.on.doc") {
                        ForEach(others) { profile in
                            Button(profile.name) { copy(from: profile.id) }
                        }
                    }
                }
            }
            if !profiles.selected.isEmpty {
                Button("Remove \(profiles.name(of: profiles.selected))", systemImage: "person.badge.minus", role: .destructive) {
                    withAnimation { profiles.remove(profiles.selected) }
                }
            }
        } label: {
            Label(profiles.name(of: profiles.selected), systemImage: "person.crop.circle")
                .labelStyle(.titleAndIcon)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let file = try JSONDecoder().decode(DashboardFile.self, from: Data(contentsOf: url))
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
                    try? file.install(homeID: homeID, memberID: profiles.selected, devices: store.devices)
                }
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert("Couldn't Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("Add Person", isPresented: $namingProfile) {
            TextField("Name", text: $newProfileName)
            Button("Add") {
                let name = newProfileName.trimmingCharacters(in: .whitespaces)
                newProfileName = ""
                guard !name.isEmpty else { return }
                withAnimation { profiles.add(name) }
            }
            Button("Cancel", role: .cancel) { newProfileName = "" }
        } message: {
            Text("Each person in the home gets their own dashboard on this device.")
        }
    }

    private func copy(from member: String) {
        let source = allCards.filter { $0.homeID == homeID && $0.memberID == member }
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
            try? DashboardFile(cards: source, devices: store.devices, groups: store.allGroups).install(homeID: homeID, memberID: profiles.selected, devices: store.devices)
        }
    }

    private func addMenu(columns: Int) -> some View {
        Menu {
            Button("Status", systemImage: "gauge.with.dots.needle.67percent") { add(.status, ref: "", columns: columns) }
                .disabled(cards.contains { $0.kind == .status })
            Menu("Room", systemImage: "square.split.bottomrightquarter") {
                ForEach(store.rooms, id: \.self) { room in
                    Button(room) { add(.room, ref: room, columns: columns) }
                        .disabled(cards.contains { $0.kind == .room && $0.ref == room })
                }
            }
            ForEach(store.rooms, id: \.self) { room in
                Menu(room) {
                    ForEach(store.devices.filter { $0.room == room && $0.kind != .camera }) { device in
                        Button(device.name, systemImage: device.icon) { add(.item, ref: device.id.uuidString, columns: columns) }
                            .disabled(cards.contains { $0.ref == device.id.uuidString })
                    }
                }
            }
            let groups = store.groups(.group)
            if !groups.isEmpty {
                Menu("Group", systemImage: "square.stack.3d.up") {
                    ForEach(groups) { group in
                        Button(group.name) { add(.group, ref: "\(group.id)", columns: columns) }
                            .disabled(cards.contains { $0.kind == .group && $0.ref == "\(group.id)" })
                    }
                }
            }
            let cameras = store.devices.filter { $0.kind == .camera }
            if !cameras.isEmpty {
                Menu("Camera", systemImage: "web.camera") {
                    ForEach(cameras) { camera in
                        Button(camera.name) { add(.camera, ref: camera.id.uuidString, columns: columns) }
                            .disabled(cards.contains { $0.ref == camera.id.uuidString })
                    }
                }
            }
            Section {
                Button("New Collection…", systemImage: "square.grid.2x2") { addingCollection = true }
                // One level deep: no folders in folders.
                if folder == nil {
                    Button("New Folder…", systemImage: "folder.badge.plus") { namingFolder = true }
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    // MARK: - Saving

    private func add(_ kind: DashboardCard.Kind, ref: String, columns: Int) {
        let size = kind.defaultSize(columns: columns)
        let spot = DashboardEngine.freeSpot(width: size.width, height: size.height, in: Array(committed(columns: columns).values), columns: columns)
        @Dependency(\.defaultDatabase) var database
        withAnimation(.spring(duration: 0.4, bounce: 0.35)) {
            try? database.write { db in
                try DashboardCard.insert {
                    DashboardCard.Draft(homeID: homeID, kind: kind, ref: ref, x: spot.x, y: spot.y, width: spot.width, height: spot.height,
                                        columns: columns, memberID: profiles.selected, folderID: folder?.id)
                }.execute(db)
            }
        }
    }

    private func remove(_ card: DashboardCard) {
        @Dependency(\.defaultDatabase) var database
        try? database.write { db in try DashboardCard.find(card.id).delete().execute(db) }
        // A collection or folder lives in its card; gone once no layout shows it any more.
        if card.kind == .collection || card.kind == .folder, let id = Int(card.ref),
           !allCards.contains(where: { $0.id != card.id && $0.kind == card.kind && $0.ref == card.ref }) {
            Groups.delete(id)
        }
        save(DashboardEngine.compact(committed(columns: columns).filter { $0.key != card.id }))
    }

    /// One transaction for the whole layout.
    private func save(_ frames: [Int: GridFrame]) {
        @Dependency(\.defaultDatabase) var database
        do {
            try database.write { db in
                for var card in cards {
                    guard let frame = frames[card.id], frame != card.frame else { continue }
                    card.frame = frame
                    try DashboardCard.update(card).execute(db)
                }
            }
        } catch {
            logger.error("Saving the dashboard failed: \(error)")
        }
    }

    private func reset() {
        @Dependency(\.defaultDatabase) var database
        let (columns, member) = (columns, profiles.selected)
        let ids = allCards.filter { $0.homeID == homeID && $0.columns == columns && $0.memberID == member && $0.folderID == folder?.id }.map(\.id)
        try? database.write { db in
            try DashboardCard.where { $0.id.in(ids) }.delete().execute(db)
        }
        UserDefaults.standard.removeObject(forKey: seededKey)
        seedIfNeeded(columns: columns)
    }

    private var seededKey: String { "dashboardSeeded.\(homeID).\(columns).\(profiles.selected)" }

    /// A first layout per home: the status, then every room. Only once, so an emptied dashboard stays empty.
    private func seedIfNeeded(columns: Int) {
        let key = seededKey
        guard folder == nil, !homeID.isEmpty, !store.devices.isEmpty, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        add(.status, ref: "", columns: columns)
        for room in store.rooms {
            add(.room, ref: room, columns: columns)
        }
    }
}

/// Edit mode wiggles the cards a little, each slightly out of step, like the Home Screen.
private struct Jiggle: ViewModifier {
    let isOn: Bool
    let seed: Int

    func body(content: Content) -> some View {
        content.phaseAnimator([false, true]) { view, phase in
            view.rotationEffect(.degrees(isOn ? (phase ? 0.8 : -0.8) : 0))
        } animation: { _ in
            isOn ? .easeInOut(duration: 0.13 + Double(seed % 5) * 0.01) : .spring(duration: 0.2)
        }
    }
}

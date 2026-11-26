import SQLiteData
import SwiftUI

/// The home at a glance, arranged freely: cards on a grid, held to move, resized from the corner.
/// 4 columns on a phone, 8 on wider screens; the same layout fits itself to both.
struct DashboardView: View {
    @Environment(HomeStore.self) private var store
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

    private var cards: [DashboardCard] {
        allCards.filter { $0.homeID == homeID && isValid($0) }
    }

    /// Cards of items or rooms that left the home are skipped, not deleted: they may come back.
    private func isValid(_ card: DashboardCard) -> Bool {
        switch card.kind {
        case .item, .camera: store.devices.contains { $0.id.uuidString == card.ref }
        case .room: store.rooms.contains(card.ref)
        case .status: true
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let columns = geometry.size.width < 600 ? 4 : 8
                let spacing: CGFloat = geometry.size.width < 600 ? 10 : 14
                let cell = max(1, (geometry.size.width - spacing * CGFloat(columns + 1)) / CGFloat(columns))
                // Rows a little shorter than wide: item cards read as tiles, not squares.
                let step = CGSize(width: cell + spacing, height: cell * 0.72 + spacing)
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
                .task(id: homeID) { seedIfNeeded(columns: columns) }
                .onChange(of: columns, initial: true) { self.columns = columns }
                #if DEBUG
                // Screenshots: `-edit YES` starts in edit mode.
                .task { isEditing = UserDefaults.standard.bool(forKey: "edit") }
                #endif
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.homeName)
            .sheet(item: $selected) { DeviceDetailView(device: $0).environment(store) }
            .sheet(item: Binding(get: { openedRoom.map(IdentifiedString.init) }, set: { openedRoom = $0?.id })) { room in
                NavigationStack {
                    RoomView(title: room.id, devices: store.devices.filter { $0.room == room.id }, showRoom: false)
                        .toolbar { Button("Done") { openedRoom = nil } }
                }
                .environment(store)
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
        .animation(.spring(duration: 0.4, bounce: 0.25), value: frames)
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
                RoomCard(room: card.ref, large: card.height > 2 || card.width > 4) { openedRoom = card.ref }
            case .status:
                StatusCard(compact: card.width < 4)
            case .camera:
                if let device = store.devices.first(where: { $0.id.uuidString == card.ref }) {
                    CameraCard(device: device)
                }
            }
        }
        .allowsHitTesting(!isEditing)
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
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
        ToolbarItem(placement: .topBarTrailing) {
            Button(isEditing ? "Done" : "Edit") {
                withAnimation(.spring(duration: 0.35, bounce: 0.3)) { isEditing.toggle() }
            }
            .fontWeight(isEditing ? .semibold : .regular)
            .disabled(store.devices.isEmpty)
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
            let cameras = store.devices.filter { $0.kind == .camera }
            if !cameras.isEmpty {
                Menu("Camera", systemImage: "web.camera") {
                    ForEach(cameras) { camera in
                        Button(camera.name) { add(.camera, ref: camera.id.uuidString, columns: columns) }
                            .disabled(cards.contains { $0.ref == camera.id.uuidString })
                    }
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    // MARK: - Saving

    private func add(_ kind: DashboardCard.Kind, ref: String, columns: Int) {
        let size = kind.defaultSize
        let spot = DashboardEngine.freeSpot(width: size.width, height: size.height, in: Array(committed(columns: columns).values), columns: columns)
        @Dependency(\.defaultDatabase) var database
        withAnimation(.spring(duration: 0.4, bounce: 0.35)) {
            try? database.write { db in
                try DashboardCard.insert {
                    DashboardCard.Draft(homeID: homeID, kind: kind, ref: ref, x: spot.x, y: spot.y, width: spot.width, height: spot.height)
                }.execute(db)
            }
        }
    }

    private func remove(_ card: DashboardCard) {
        @Dependency(\.defaultDatabase) var database
        try? database.write { db in try DashboardCard.find(card.id).delete().execute(db) }
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
        try? database.write { db in try DashboardCard.where { $0.homeID.eq(homeID) }.delete().execute(db) }
        UserDefaults.standard.removeObject(forKey: "dashboardSeeded.\(homeID)")
        seedIfNeeded(columns: columns)
    }

    /// A first layout per home: the status, then every room. Only once, so an emptied dashboard stays empty.
    private func seedIfNeeded(columns: Int) {
        let key = "dashboardSeeded.\(homeID)"
        guard !homeID.isEmpty, !store.devices.isEmpty, !UserDefaults.standard.bool(forKey: key) else { return }
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

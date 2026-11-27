import SQLiteData
import SwiftUI

/// "Open for 5 minutes", from the saved history; "at least" when the app missed the moment it changed.
struct SinceText: View {
    let device: Device
    @Environment(HomeStore.self) private var store

    var body: some View {
        if let event = store.since[device.id], event.isActive == device.isActive {
            // Updates itself.
            Text(event.notSeenSince == nil
                ? "\(device.stateName(active: event.isActive)) for \(event.date, style: .relative)"
                : "\(device.stateName(active: event.isActive)) for at least \(event.date, style: .relative)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// When an item switched over the last 30 days, newest first.
struct ItemHistory: View {
    let device: Device
    @FetchAll private var events: [ItemEvent]

    init(device: Device) {
        self.device = device
        _events = FetchAll(ItemEvent.where { $0.deviceID.eq(device.id) }.order { $0.date.desc() }.limit(200))
    }

    var body: some View {
        let runs = Self.runs(events)
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("History").font(.headline)
                ForEach(runs) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(event.isActive ? AnyShapeStyle(device.kind.tint) : AnyShapeStyle(.quaternary))
                            .frame(width: 10, height: 10)
                        Text(device.stateName(active: event.isActive))
                        Spacer()
                        Text(time(event)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(.subheadline)
                }
            }
            .padding()
            .background(.regularMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        }
    }

    /// Each device saves what it sees, so two can save the same change: keep only the first of a run of one state.
    static func runs(_ newestFirst: [ItemEvent]) -> [ItemEvent] {
        newestFirst.indices.compactMap { index in
            index + 1 < newestFirst.count && newestFirst[index + 1].isActive == newestFirst[index].isActive ? nil : newestFirst[index]
        }
    }

    private func time(_ event: ItemEvent) -> String {
        let format = Date.FormatStyle().day().month(.abbreviated).hour().minute()
        switch event.notSeenSince {
        case nil: return event.date.formatted(format)
        case .distantPast: return "before \(event.date.formatted(format))"
        case let start?:
            // The end's day only when it differs: "3 Nov 14:02 – 15:10".
            let end = Calendar.current.isDate(start, inSameDayAs: event.date) ? event.date.formatted(date: .omitted, time: .shortened) : event.date.formatted(format)
            return "\(start.formatted(format)) – \(end)"
        }
    }
}

#if DEBUG
/// Runs once at launch in debug builds: the same change saved by two devices shows once, at its first sighting.
@MainActor
func checkHistoryRuns() {
    let event = { (active: Bool, minutes: Double) in
        ItemEvent(id: UUID(), homeID: "a", deviceID: UUID(), isActive: active, date: Date(timeIntervalSince1970: minutes * 60))
    }
    let runs = ItemHistory.runs([event(true, 5), event(true, 4), event(false, 2), event(true, 1)])
    assert(runs.map(\.isActive) == [true, false, true] && runs[0].date == Date(timeIntervalSince1970: 240))
}
#endif

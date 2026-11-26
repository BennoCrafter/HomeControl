import CoreGraphics

/// A card's place on the grid, in cells.
struct GridFrame: Hashable {
    var x, y, width, height: Int

    var maxX: Int { x + width }
    var maxY: Int { y + height }

    func overlaps(_ other: GridFrame) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }
}

extension DashboardCard {
    var frame: GridFrame {
        get { GridFrame(x: x, y: y, width: width, height: height) }
        set { (x, y, width, height) = (newValue.x, newValue.y, newValue.width, newValue.height) }
    }
}

extension DashboardCard.Kind {
    var minSize: (width: Int, height: Int) {
        switch self {
        case .item: (2, 1)
        case .status: (2, 1)
        case .room, .camera: (2, 2)
        }
    }

    var defaultSize: (width: Int, height: Int) {
        switch self {
        case .item: (2, 1)
        case .status: (4, 1)
        case .room: (2, 2)
        case .camera: (2, 2)
        }
    }
}

/// Free of SwiftUI state, so the same functions drive the live drag preview and the drop.
/// Ported from Timetable's dashboard.
enum DashboardEngine {
    /// Overlapped cards are pushed down in reading order, then all but the moved one compact upward,
    /// so the dropped card stays exactly where it was placed.
    static func relayout(_ frames: [Int: GridFrame], moving id: Int, to desired: GridFrame, columns: Int) -> [Int: GridFrame] {
        var moved = desired
        moved.width = min(moved.width, columns)
        moved.x = max(0, min(moved.x, columns - moved.width))
        moved.y = max(0, moved.y)
        var placed: [Int: GridFrame] = [id: moved]
        for (other, frame) in frames.filter({ $0.key != id }).sorted(by: { ($0.value.y, $0.value.x) < ($1.value.y, $1.value.x) }) {
            var settled = frame
            while placed.values.contains(where: { $0.overlaps(settled) }) {
                settled.y += 1
            }
            placed[other] = settled
        }
        return compact(placed, pinned: id)
    }

    /// Top to bottom, so each card only compacts against already settled neighbours.
    static func compact(_ frames: [Int: GridFrame], pinned: Int? = nil) -> [Int: GridFrame] {
        var result: [Int: GridFrame] = [:]
        if let pinned, let frame = frames[pinned] {
            result[pinned] = frame
        }
        for (id, frame) in frames.filter({ $0.key != pinned }).sorted(by: { ($0.value.y, $0.value.x) < ($1.value.y, $1.value.x) }) {
            var candidate = frame
            while candidate.y > 0 {
                var trial = candidate
                trial.y -= 1
                if result.values.contains(where: { $0.overlaps(trial) }) { break }
                candidate = trial
            }
            result[id] = candidate
        }
        return result
    }

    /// A narrower screen than the layout was made on: cards too wide shrink, then everything settles.
    static func fit(_ frames: [Int: GridFrame], columns: Int) -> [Int: GridFrame] {
        var fitted = frames.mapValues { frame in
            var frame = frame
            frame.width = min(frame.width, columns)
            frame.x = min(frame.x, columns - frame.width)
            return frame
        }
        // Resolve overlaps the shrinking caused, in reading order.
        var placed: [Int: GridFrame] = [:]
        for (id, frame) in fitted.sorted(by: { ($0.value.y, $0.value.x) < ($1.value.y, $1.value.x) }) {
            var settled = frame
            while placed.values.contains(where: { $0.overlaps(settled) }) {
                settled.y += 1
            }
            placed[id] = settled
        }
        fitted = placed
        return compact(fitted)
    }

    /// The first free spot for a new card, scanning rows top to bottom.
    static func freeSpot(width: Int, height: Int, in frames: [GridFrame], columns: Int) -> GridFrame {
        let width = min(width, columns)
        for y in 0 ... (frames.map(\.maxY).max() ?? 0) {
            for x in 0 ... (columns - width) {
                let candidate = GridFrame(x: x, y: y, width: width, height: height)
                if !frames.contains(where: { $0.overlaps(candidate) }) { return candidate }
            }
        }
        return GridFrame(x: 0, y: frames.map(\.maxY).max() ?? 0, width: width, height: height)
    }

    static func cellDelta(for translation: CGSize, step: CGSize) -> (dx: Int, dy: Int) {
        guard step.width > 0, step.height > 0 else { return (0, 0) }
        return (Int((translation.width / step.width).rounded()), Int((translation.height / step.height).rounded()))
    }
}

#if DEBUG
    /// Runs once at launch in debug builds; there is no test target.
    func checkDashboardEngine() {
        let a = GridFrame(x: 0, y: 0, width: 2, height: 1)
        let b = GridFrame(x: 2, y: 0, width: 2, height: 2)
        assert(!a.overlaps(b) && a.overlaps(GridFrame(x: 1, y: 0, width: 2, height: 1)))
        // Dropping a onto b pushes b below it.
        let moved = DashboardEngine.relayout([1: a, 2: b], moving: 1, to: GridFrame(x: 2, y: 0, width: 2, height: 1), columns: 4)
        assert(moved[1] == GridFrame(x: 2, y: 0, width: 2, height: 1) && moved[2]!.y == 1)
        // A gap closes upward.
        assert(DashboardEngine.compact([1: GridFrame(x: 0, y: 3, width: 2, height: 1)])[1]!.y == 0)
        // Too wide for a phone: shrinks to the columns and stacks.
        let fitted = DashboardEngine.fit([1: GridFrame(x: 0, y: 0, width: 8, height: 1), 2: GridFrame(x: 4, y: 1, width: 4, height: 1)], columns: 4)
        assert(fitted[1]!.width == 4 && fitted[2]!.x == 0 && fitted[2]!.y == 1)
        assert(DashboardEngine.freeSpot(width: 2, height: 1, in: [a], columns: 4) == GridFrame(x: 2, y: 0, width: 2, height: 1))
    }
#endif

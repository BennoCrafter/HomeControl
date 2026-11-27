import SwiftUI
import UIKit.UIGestureRecognizerSubclass

enum DragHandle: Equatable {
    case move, resize
}

/// UIKit, not SwiftUI's `LongPressGesture.sequenced(before: DragGesture)`, which kept the ScrollView
/// from scrolling when a swipe started on a card. Ported from Timetable's dashboard.
/// Locations are in `.global` space, which moves with neither the card nor the scrolling content.
struct HoldToDrag: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var minimumDuration: Double = 0.2
    /// The resize grip starts without the hold; waiting on a grab handle feels broken.
    var handle: (CGPoint) -> DragHandle
    var onChanged: (DragHandle, CGSize) -> Void
    var onEnded: (DragHandle, CGSize) -> Void
    var onCancelled: () -> Void

    final class Recognizer: UILongPressGestureRecognizer {
        var holdDuration: Double = 0
        var handle: ((CGPoint) -> DragHandle)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            // Before `super` starts the hold timer. Window coordinates are SwiftUI's `.global`.
            let onGrip = touches.first.map { handle?($0.location(in: nil)) ?? .move } == .resize
            minimumPressDuration = onGrip ? 0 : holdDuration
            super.touchesBegan(touches, with: event)
        }
    }

    final class Coordinator {
        var start: CGPoint = .zero
        var handle = DragHandle.move
    }

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> Recognizer {
        let recognizer = Recognizer()
        recognizer.holdDuration = minimumDuration
        updateUIGestureRecognizer(recognizer, context: context)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: Recognizer, context _: Context) {
        recognizer.isEnabled = isEnabled
        recognizer.handle = handle
    }

    func handleUIGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
        let location = context.converter.location(in: .global)
        let state = context.coordinator
        let translation = CGSize(width: location.x - state.start.x, height: location.y - state.start.y)
        switch recognizer.state {
        case .began:
            state.start = location
            state.handle = handle(location)
            onChanged(state.handle, .zero)
        case .changed:
            onChanged(state.handle, translation)
        case .ended:
            onEnded(state.handle, translation)
        default:
            onCancelled()
        }
    }
}

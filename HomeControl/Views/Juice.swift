import SwiftUI

/// Squishes while held and springs back: every tappable thing in the app feels physical.
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
    }
}

extension EnvironmentValues {
    /// How solid the tiles are over the background : 0 clear, 1 solid.
    @Entry var tileOpacity = 1.0
}

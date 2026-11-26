import HomeKit
import SwiftUI

/// A camera's picture: a snapshot refreshed every 10 seconds, or the live stream.
/// HomeKit draws both into its own `HMCameraView`.
@MainActor @Observable
final class CameraFeed: NSObject {
    private(set) var source: HMCameraSource?
    private(set) var failed = false
    @ObservationIgnored private let profile: HMCameraProfile?
    @ObservationIgnored private var refresher: Task<Void, Never>?

    init(profile: HMCameraProfile?) {
        self.profile = profile
        super.init()
        profile?.snapshotControl?.delegate = self
        profile?.streamControl?.delegate = self
    }

    func startSnapshots() {
        guard let control = profile?.snapshotControl else { return }
        source = control.mostRecentSnapshot
        refresher?.cancel()
        refresher = Task { [weak control] in
            while !Task.isCancelled {
                control?.takeSnapshot()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func startStream() {
        profile?.streamControl?.startStream()
    }

    func stop() {
        refresher?.cancel()
        profile?.streamControl?.stopStream()
    }
}

// HomeKit delivers camera callbacks on the main queue.
extension CameraFeed: HMCameraSnapshotControlDelegate, HMCameraStreamControlDelegate {
    nonisolated func cameraSnapshotControl(_ control: HMCameraSnapshotControl, didTake snapshot: HMCameraSnapshot?, error: Error?) {
        MainActor.assumeIsolated {
            if let snapshot { source = snapshot }
            failed = snapshot == nil && source == nil
        }
    }

    nonisolated func cameraStreamControlDidStartStream(_ control: HMCameraStreamControl) {
        MainActor.assumeIsolated { source = control.cameraStream }
    }

    nonisolated func cameraStreamControl(_ control: HMCameraStreamControl, didStopStreamWithError error: Error?) {
        MainActor.assumeIsolated { failed = error != nil }
    }
}

private struct HomeKitCameraView: UIViewRepresentable {
    let source: HMCameraSource?

    func makeUIView(context _: Context) -> HMCameraView {
        HMCameraView()
    }

    func updateUIView(_ view: HMCameraView, context _: Context) {
        view.cameraSource = source
    }
}

/// The picture, or something alive while there is none (and in the demo home).
struct CameraPicture: View {
    let feed: CameraFeed

    var body: some View {
        ZStack {
            if feed.source != nil {
                HomeKitCameraView(source: feed.source)
                    .transition(.opacity)
            } else {
                // A slow drifting gradient stands in for the picture.
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    LinearGradient(colors: [.indigo, .blue, .teal], startPoint: UnitPoint(x: 0.5 + 0.5 * sin(t / 3), y: 0),
                                   endPoint: UnitPoint(x: 0.5 - 0.5 * sin(t / 3), y: 1))
                        .overlay {
                            Image(systemName: feed.failed ? "video.slash.fill" : "web.camera.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: feed.source == nil)
    }
}

/// A dashboard card with the camera's snapshot; tap for the live picture.
struct CameraCard: View {
    let device: Device
    @Environment(HomeStore.self) private var store
    @State private var feed: CameraFeed?
    @State private var showingLive = false

    var body: some View {
        Button { showingLive = true } label: {
            ZStack(alignment: .bottomLeading) {
                if let feed {
                    CameraPicture(feed: feed)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 7, height: 7)
                        .phaseAnimator([1.0, 0.3]) { $0.opacity($1) } animation: { _ in .easeInOut(duration: 0.8) }
                    Text(device.name).font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .padding(12)
            }
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.96))
        .task {
            let feed = CameraFeed(profile: store.cameras[device.id])
            self.feed = feed
            feed.startSnapshots()
        }
        .onDisappear { feed?.stop() }
        .fullScreenCover(isPresented: $showingLive) { LiveCameraView(device: device).environment(store) }
        .sensoryFeedback(.impact(weight: .light), trigger: showingLive)
    }
}

/// Fullscreen live picture.
struct LiveCameraView: View {
    let device: Device
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var feed: CameraFeed?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let feed {
                CameraPicture(feed: feed)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Label(device.name, systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: .circle)
                }
                .buttonStyle(PressScale(scale: 0.85))
                .accessibilityLabel("Close")
            }
            .padding()
        }
        .task {
            let feed = CameraFeed(profile: store.cameras[device.id])
            self.feed = feed
            feed.startStream()
        }
        .onDisappear { feed?.stop() }
    }
}

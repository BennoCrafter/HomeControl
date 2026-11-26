import HomeKit
import SwiftUI

/// A camera's picture: a snapshot refreshed every 10 seconds, or the live stream.
/// HomeKit draws both into its own `HMCameraView`. One feed per camera, shared by every view showing it:
/// a camera control has a single delegate, so two feeds would steal each other's pictures.
@MainActor @Observable
final class CameraFeed: NSObject {
    private(set) var source: HMCameraSource?
    private(set) var failed = false
    private(set) var isLive = false
    /// When the picture on screen was taken; nil while live.
    private(set) var capturedAt: Date?
    @ObservationIgnored private let profile: HMCameraProfile?
    @ObservationIgnored private var refresher: Task<Void, Never>?
    @ObservationIgnored private var snapshotViewers = 0
    @ObservationIgnored private var latestSnapshot: HMCameraSnapshot?

    private static var feeds: [UUID: CameraFeed] = [:]

    static func feed(for profile: HMCameraProfile?) -> CameraFeed {
        guard let profile else { return CameraFeed(profile: nil) }
        if let feed = feeds[profile.uniqueIdentifier] { return feed }
        let feed = CameraFeed(profile: profile)
        feeds[profile.uniqueIdentifier] = feed
        return feed
    }

    private init(profile: HMCameraProfile?) {
        self.profile = profile
        super.init()
        profile?.snapshotControl?.delegate = self
        profile?.streamControl?.delegate = self
        latestSnapshot = profile?.snapshotControl?.mostRecentSnapshot
        source = latestSnapshot
        capturedAt = latestSnapshot?.captureDate
    }

    func startSnapshots() {
        snapshotViewers += 1
        guard snapshotViewers == 1, let control = profile?.snapshotControl else { return }
        refresher = Task { [weak control] in
            while !Task.isCancelled {
                control?.takeSnapshot()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stopSnapshots() {
        snapshotViewers = max(0, snapshotViewers - 1)
        if snapshotViewers == 0 { refresher?.cancel() }
    }

    func startStream() {
        profile?.streamControl?.startStream()
    }

    func stopStream() {
        profile?.streamControl?.stopStream()
    }
}

// HomeKit delivers camera callbacks on the main queue.
extension CameraFeed: HMCameraSnapshotControlDelegate, HMCameraStreamControlDelegate {
    nonisolated func cameraSnapshotControl(_ control: HMCameraSnapshotControl, didTake snapshot: HMCameraSnapshot?, error: Error?) {
        MainActor.assumeIsolated {
            if let snapshot {
                latestSnapshot = snapshot
                if !isLive {
                    source = snapshot
                    capturedAt = snapshot.captureDate
                }
            }
            failed = snapshot == nil && source == nil
        }
    }

    nonisolated func cameraStreamControlDidStartStream(_ control: HMCameraStreamControl) {
        MainActor.assumeIsolated {
            source = control.cameraStream
            isLive = true
            capturedAt = nil
        }
    }

    nonisolated func cameraStreamControl(_ control: HMCameraStreamControl, didStopStreamWithError error: Error?) {
        MainActor.assumeIsolated {
            isLive = false
            source = latestSnapshot
            capturedAt = latestSnapshot?.captureDate
            failed = error != nil && source == nil
        }
    }
}

private struct HomeKitCameraView: UIViewRepresentable {
    let source: HMCameraSource?
    /// Gets a still of each snapshot, for the camera widget.
    var still: ((UIImage) -> Void)?

    func makeUIView(context _: Context) -> HMCameraView {
        HMCameraView()
    }

    func updateUIView(_ view: HMCameraView, context _: Context) {
        guard view.cameraSource !== source else { return }
        view.cameraSource = source
        guard let still, source is HMCameraSnapshot else { return }
        Task {
            // HomeKit offers no image of a snapshot; a moment after it's drawn, take one from the view.
            try? await Task.sleep(for: .milliseconds(600))
            guard view.bounds.width > 0 else { return }
            let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            still(image)
        }
    }
}

/// The picture, or something alive while there is none (and in the demo home).
struct CameraPicture: View {
    let feed: CameraFeed
    var cameraID: UUID?

    var body: some View {
        ZStack {
            if feed.source != nil {
                HomeKitCameraView(source: feed.source) { image in
                    if let cameraID, let data = image.preparingThumbnail(of: CGSize(width: 640, height: 640 * image.size.height / max(image.size.width, 1)))?.jpegData(compressionQuality: 0.7) {
                        WidgetData.saveCameraImage(data, for: cameraID)
                    }
                }
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

/// "Live", or how old the picture is.
struct CameraBadge: View {
    let feed: CameraFeed

    var body: some View {
        Group {
            if feed.isLive {
                Text("Live")
            } else if let capturedAt = feed.capturedAt {
                Text(capturedAt, style: .relative)
            }
        }
        .font(.caption.bold().monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.35), in: .capsule)
        .contentTransition(.numericText())
    }
}

/// A dashboard card with the camera's snapshot; tap for the live picture.
struct CameraCard: View {
    let device: Device
    @Environment(HomeStore.self) private var store
    @State private var showingLive = false

    var body: some View {
        let feed = CameraFeed.feed(for: store.cameras[device.id])
        Button { showingLive = true } label: {
            ZStack(alignment: .bottomLeading) {
                CameraPicture(feed: feed, cameraID: device.id)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                HStack {
                    Text(device.name).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    CameraBadge(feed: feed)
                }
                .foregroundStyle(.white)
                .padding(12)
            }
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.96))
        // Again once HomeKit has handed over the camera: at launch it isn't there yet.
        .task(id: store.cameras[device.id]) {
            feed.startSnapshots()
            await untilCancelled()
            feed.stopSnapshots()
        }
        .fullScreenCover(isPresented: $showingLive) { LiveCameraView(device: device).environment(store) }
        .sensoryFeedback(.impact(weight: .light), trigger: showingLive)
    }
}

/// Fullscreen live picture.
struct LiveCameraView: View {
    let device: Device
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let feed = CameraFeed.feed(for: store.cameras[device.id])
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            CameraPicture(feed: feed, cameraID: device.id)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(device.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                CameraBadge(feed: feed)
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
            feed.startStream()
            await untilCancelled()
            feed.stopStream()
        }
    }
}

/// Suspends until the view's task is cancelled, when it disappears.
private func untilCancelled() async {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3600))
    }
}

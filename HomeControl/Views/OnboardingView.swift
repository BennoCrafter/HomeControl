import SwiftUI

extension URL {
    /// Where the user can grant Home access after denying it.
    static var homeAccessSettings: URL {
        #if targetEnvironment(macCatalyst)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_HomeKit")!
        #else
        URL(string: UIApplication.openSettingsURLString)!
        #endif
    }
}

struct OnboardingView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @State private var page = 0

    private let lastPage = 2

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingPage(symbol: nil, title: "Welcome to HomeControl",
                               text: "Your Apple Home on iPhone, iPad and Mac. Fast, clear and always within reach.") {
                    EmptyView()
                }
                .tag(0)

                OnboardingPage(symbol: "dial.high.fill", title: "Made for touch",
                               text: "Every control is built to feel right under your finger.") {
                    VStack(alignment: .leading, spacing: 18) {
                        FeatureRow(symbol: "lightbulb.fill", title: "Lights",
                                   text: "Turn the dial and watch the brightness follow live.")
                        FeatureRow(symbol: "blinds.horizontal.open", title: "Shutters",
                                   text: "Slide to open or close, with a haptic tick every 10%.")
                        FeatureRow(symbol: "door.garage.closed", title: "Locks & garage doors",
                                   text: "Opening and unlocking always asks first.")
                        FeatureRow(symbol: "dot.radiowaves.left.and.right", title: "Always in sync",
                                   text: "Changes from the Home app and your devices appear instantly.")
                    }
                }
                .tag(1)

                OnboardingPage(symbol: "homekit", title: "Connect to Apple Home",
                               text: "HomeControl needs access to your Home data to show and control your accessories. It stays between your devices and Apple Home.") {
                    accessStatus
                }
                .tag(2)
            }
            // Own dots, outside the pages: the system's sat on top of a long page's last lines.
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(0 ... lastPage, id: \.self) { index in
                    Circle()
                        .fill(.white.opacity(index == page ? 1 : 0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .padding(.vertical, 16)
            .accessibilityHidden(true)

            buttons
                .padding(.horizontal, 32)
                .padding(.bottom, 4) // the home indicator's safe area already leaves room
                .frame(maxWidth: 480)
        }
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.39, green: 0.70, blue: 1), Color(red: 0.18, green: 0.49, blue: 0.96)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.success, trigger: store.access == .authorized)
        #if DEBUG
        // Screenshots: `-onboardingPage 1` starts on that page.
        .task { page = UserDefaults.standard.integer(forKey: "onboardingPage") }
        #endif
    }

    @ViewBuilder private var accessStatus: some View {
        switch store.access {
        case .notRequested: EmptyView()
        case .pending: ProgressView().tint(.white)
        case .authorized: Label("Access granted", systemImage: "checkmark.circle.fill").font(.headline)
        case .denied:
            Label("Access was denied. You can turn it on in Settings.", systemImage: "exclamationmark.circle.fill")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private var buttons: some View {
        VStack(spacing: 12) {
            if page < lastPage {
                primaryButton("Continue") { withAnimation { page += 1 } }
                secondaryButton("Skip") { withAnimation { page = lastPage } }
            } else {
                switch store.access {
                case .notRequested, .pending:
                    primaryButton("Allow Home Access") { store.requestAccess() }
                        .disabled(store.access == .pending)
                    secondaryButton("Explore the Demo Home") { store.selectHome(HomeOption.demo.id); finish() }
                    secondaryButton("Not Now") { finish() }
                case .authorized:
                    primaryButton("Get Started") { finish() }
                case .denied:
                    primaryButton("Open Settings") { openURL(.homeAccessSettings) }
                    secondaryButton("Explore the Demo Home") { store.selectHome(HomeOption.demo.id); finish() }
                    secondaryButton("Continue Anyway") { finish() }
                }
            }
        }
    }

    private func finish() {
        withAnimation(.smooth(duration: 0.45)) { hasOnboarded = true }
    }

    private func primaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.white)
        .foregroundStyle(Color.accentColor)
        .keyboardShortcut(.defaultAction) // Return continues
    }

    private func secondaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .buttonStyle(.plain)
            .frame(minHeight: 32)
    }
}

private struct OnboardingPage<Content: View>: View {
    /// SF Symbol for the hero; nil shows the app logo.
    let symbol: String?
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder let content: Content
    @State private var appeared = false
    /// Short screens (iPhone mini, SE) get a smaller hero, so a page fits without scrolling.
    @State private var isShort = false

    var body: some View {
        ScrollView {
            VStack(spacing: isShort ? 16 : 24) {
                hero
                    .frame(width: isShort ? 104 : 148, height: isShort ? 104 : 148)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                    .padding(.top, isShort ? 16 : 48)
                VStack(spacing: 10) {
                    Text(title).font(.largeTitle.bold())
                    Text(text).font(.body).foregroundStyle(.white.opacity(0.85))
                }
                .multilineTextAlignment(.center)
                content
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: Bool.self) { $0.size.height < 700 } action: { isShort = $0 }
        .onAppear { appeared.toggle() }
    }

    @ViewBuilder private var hero: some View {
        if let symbol {
            Image(systemName: symbol)
                .font(.system(size: isShort ? 46 : 64, weight: .medium))
                .symbolEffect(.bounce, value: appeared)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.18), in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
        } else {
            Image("Logo")
                .resizable()
                .clipShape(.rect(cornerRadius: 33, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 33, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

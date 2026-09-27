import SwiftUI
import SwiftData
import UserNotifications

@main
struct MuonApp: App {
    @State private var host: AppHost
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = ForegroundNotifications()

    init() {
        #if DEBUG
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        let demo = false
        #endif
        _host = State(initialValue: AppHost(demo: demo))
        UNUserNotificationCenter.current().delegate = notificationDelegate
        Typography.styleNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(ObjectIdentifier(host.app))          // rebuild the tree when switching to or from the demo
                .environment(host)
                .environment(host.app)
                .modelContainer(host.app.container)
                .tint(Palette.violet)
                .preferredColorScheme(.dark)             // the design is dark-only
                .font(Typography.body)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { host.app.link.refresh(); host.app.refreshPhase() }
        }
    }
}

/// Owns the current AppModel so "Try the demo instead" can swap in an in-memory
/// demo session without touching the user's stored runs, and switch back.
@Observable
@MainActor
final class AppHost {
    private(set) var app: AppModel

    init(demo: Bool) { app = Self.make(demo: demo) }

    func enterDemo() {
        guard !app.demo, !app.logging else { return }
        app = Self.make(demo: true)
    }
    func exitDemo() {
        guard app.demo else { return }
        app = Self.make(demo: false)
    }

    private static func make(demo: Bool) -> AppModel {
        let schema = Schema([Run.self, Minute.self, RunEvent.self])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: demo))
        } catch {
            // A store that cannot open must not stop logging; fall back to memory and say so.
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        return AppModel(container: container, demo: demo)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case now, runs, detector, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .now: "dot.radiowaves.left.and.right"
        case .runs: "list.bullet"
        case .detector: "cpu"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @SceneStorage("tab") private var tab: AppTab = .now
    @State private var showPair = false
    /// Debug switch: Apple's iOS 26 tab bar and bottom accessory instead of the
    /// custom chamfered bars. `defaults write <bundle id> useSystemTabBar -bool YES`,
    /// or the toggle under Settings › Debug in Debug builds.
    @AppStorage("useSystemTabBar") private var useSystemTabBar = false

    var body: some View {
        Group {
            if useSystemTabBar { systemTabs } else { customTabs }
        }
        .sheet(isPresented: $showPair) { PairView() }
        .onOpenURL { url in if let host = url.host(), let t = AppTab(rawValue: host) { tab = t } }
    }

    @ViewBuilder private func screen(_ t: AppTab) -> some View {
        switch t {
        case .now: NowView()
        case .runs: RunsView()
        case .detector: DetectorView()
        case .settings: SettingsView()
        }
    }

    private var systemTabs: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { t in
                Tab(t.title, systemImage: t.symbol, value: t) { screen(t) }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { LoggingBar(showPair: $showPair, floating: false) }
    }

    /// Custom floating bars. Each screen keeps its own navigation state inside
    /// the (hidden) system TabView; a clear inset reserves room under the content.
    private var customTabs: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { t in
                Tab(t.title, systemImage: t.symbol, value: t) {
                    screen(t)
                        .toolbarVisibility(.hidden, for: .tabBar)
                        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: FloatingBars.reservedHeight) }
                }
            }
        }
        .overlay(alignment: .bottom) {
            FloatingBars(tab: $tab, showPair: $showPair)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

/// Logging bar stacked above the tab bar, both frosted and chamfered.
struct FloatingBars: View {
    @Binding var tab: AppTab
    @Binding var showPair: Bool
    static let reservedHeight: CGFloat = 132

    var body: some View {
        VStack(spacing: 8) {
            LoggingBar(showPair: $showPair, floating: true)
            ChamferTabBar(selection: $tab)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

struct ChamferTabBar: View {
    @Binding var selection: AppTab
    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { t in
                let on = t == selection
                Button { selection = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.symbol).font(.system(size: 17, weight: .medium))
                        Text(t.title).font(Typography.raleway(11, .semibold, relativeTo: .caption2)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? Palette.ink : Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background { if on { ChamferedShape.control(8).fill(Palette.violet.opacity(0.18)) } }
                    .overlay { if on { ChamferedShape.control(8).strokeBorder(Palette.brightEdge, lineWidth: 1) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(5)
        .chamferGlass(.control(12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }
}

/// Logging state and one start/stop control, on every tab.
struct LoggingBar: View {
    @Environment(AppModel.self) private var app
    @Binding var showPair: Bool
    var floating: Bool

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(app.logging ? Palette.pink : Palette.secondaryText).frame(width: 8, height: 8).rotationEffect(.degrees(45))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.logging ? "Logging · \(app.currentRun?.name ?? "")" : "Not logging")
                    .font(Typography.raleway(15, .bold, relativeTo: .subheadline)).lineLimit(1)
                if app.logging, let start = app.currentRun?.start {
                    HStack(spacing: 4) {
                        Text(start, style: .timer).monospacedDigit()
                        if app.cloud.lastSave != nil { Text("· saved to \(app.cloud.folderName ?? "cosmic")").lineLimit(1) }
                    }
                    .font(Typography.monoCaption).foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: 6)
            Button {
                if app.logging { app.stop() } else if app.needsPairing { showPair = true } else { app.start() }
            } label: {
                Image(systemName: app.logging ? "stop.fill" : "record.circle")
            }
            .buttonStyle(.muonIcon)
            .accessibilityLabel(app.logging ? "Stop logging" : "Start logging")
            .disabled(app.demo)
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
        .modifier(OptionalGlass(on: floating))
    }
}

private struct OptionalGlass: ViewModifier {
    let on: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if on { content.chamferGlass(.control(10)) } else { content.padding(.horizontal, 4) }
    }
}

/// Show alerts as banners even while the app is open.
final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

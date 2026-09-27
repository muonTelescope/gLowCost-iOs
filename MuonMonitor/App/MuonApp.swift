import SwiftUI
import SwiftData
import UserNotifications

@main
struct MuonApp: App {
    @State private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = ForegroundNotifications()

    init() {
        #if DEBUG
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        let demo = false
        #endif
        let schema = Schema([Run.self, Minute.self, RunEvent.self])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: demo))
        } catch {
            // A store that cannot open must not stop logging; fall back to memory and say so.
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
        _app = State(initialValue: AppModel(container: container, demo: demo))
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .modelContainer(app.container)
                .tint(Palette.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.link.refresh(); app.refreshPhase() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @SceneStorage("tab") private var tab = "now"
    @State private var showPair = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Now", systemImage: "dot.radiowaves.left.and.right", value: "now") { NowView() }
            Tab("Runs", systemImage: "list.bullet", value: "runs") { RunsView() }
            Tab("Detector", systemImage: "cpu", value: "detector") { DetectorView() }
            Tab("Settings", systemImage: "gearshape", value: "settings") { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { LoggingAccessory(showPair: $showPair) }
        .sheet(isPresented: $showPair) { PairView() }
        .onOpenURL { url in if let host = url.host(), ["now", "runs", "detector", "settings"].contains(host) { tab = host } }
    }
}

/// The bar above the tab bar: logging state and one start/stop control, on every tab.
struct LoggingAccessory: View {
    @Environment(AppModel.self) private var app
    @Binding var showPair: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(app.logging ? Palette.danger : Palette.secondaryText).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.logging ? "Logging · \(app.currentRun?.name ?? "")" : "Not logging").font(.subheadline.weight(.semibold)).lineLimit(1)
                if app.logging, let start = app.currentRun?.start {
                    HStack(spacing: 4) {
                        Text(start, style: .timer).monospacedDigit()
                        if app.cloud.lastSave != nil { Text("· saved to \(app.cloud.folderName ?? "cosmic")") }
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                if app.logging { app.stop() } else if app.needsPairing { showPair = true } else { app.start() }
            } label: {
                Image(systemName: app.logging ? "stop.fill" : "record.circle").frame(width: 30, height: 30)
            }
            .accessibilityLabel(app.logging ? "Stop logging" : "Start logging")
            .disabled(app.demo)
        }
        .padding(.horizontal, 16)
    }
}

/// Show alerts as banners even while the app is open.
final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

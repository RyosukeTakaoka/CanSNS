import SwiftUI

@main
struct CanSNSApp: App {
    @State private var store = AppStore()

    init() {
        // ドットフォント（DotGothic16）を使えるようにする
        PixelFont.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

/// 状態に合わせて最初に見せる画面を切り替える
struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if case .failed(let message) = store.cloudStatus {
                ConnectionErrorView(message: message)
            } else if store.isLoading {
                LaunchView()
            } else if store.currentUser == nil {
                OnboardingView()
            } else if store.currentMachine == nil {
                NavigationStack {
                    MachineSetupView()
                }
            } else {
                MainTabView()
            }
        }
        .animation(.default, value: store.currentUserID)
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("自販機", systemImage: "house.fill") }
            FridgeView()
                .tabItem { Label("冷蔵庫", systemImage: "refrigerator.fill") }
            NotificationsView()
                .tabItem { Label("お知らせ", systemImage: "bell.fill") }
                .badge(store.unreadCount)
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
        }
        // 強調色は青（赤はドット絵の自販機と「削除」だけに使う）
        .tint(Pixel.blue)
        .toast(Binding(get: { store.syncMessage }, set: { store.syncMessage = $0 }))
    }
}

/// Firebase に接続しているあいだの画面
struct LaunchView: View {
    @Environment(AppStore.self) private var store
    @State private var sceneDate = Date()

    var body: some View {
        ZStack {
            SkyBackgroundView(date: store.adjusted(sceneDate), calendar: store.clock.calendar)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                CanView(title: "CanSNS", mood: .cold, kind: .text, pattern: .stripe, emoji: "🥫", width: 70)
                Text("自販機に電気を入れています…")
                    .font(.pixel(16))
                    .pixelWindow()
                    .fixedSize()
            }
        }
    }
}

/// Firebase に接続できなかったときの画面
struct ConnectionErrorView: View {
    @Environment(AppStore.self) private var store
    var message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("サーバーにつながりませんでした")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("もう一度つなぐ") { store.retryConnection() }
                .buttonStyle(.borderedProminent)
            Button("オフライン（デモ）モードで使う") { store.setLocalMode(true) }
                .font(.footnote)
        }
        .padding(32)
    }
}

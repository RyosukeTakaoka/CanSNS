import SwiftUI

@main
struct CanSNSApp: App {
    @State private var store = AppStore()

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
            if store.currentUser == nil {
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
        .tint(Theme.machineBody)
    }
}

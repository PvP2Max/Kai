import SwiftUI

@main
struct KaiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var navigationCoordinator = NavigationCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                        .environmentObject(navigationCoordinator)
                } else if authManager.requiresBiometric {
                    BiometricPromptView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(authManager)
            .environmentObject(networkMonitor)
            .onAppear {
                configureAppearance()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    navigationCoordinator.checkForPendingNavigation()

                    // Sync reminders when app becomes active
                    if authManager.isAuthenticated {
                        RemindersManager.shared.syncInBackground()
                    }
                }
            }
        }
    }

    private func configureAppearance() {
        // Configure navigation bar appearance
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance

        // Configure tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
}

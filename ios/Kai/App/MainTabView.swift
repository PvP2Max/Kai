import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Tab = .chat
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var networkMonitor: NetworkMonitor

    enum Tab: Int, CaseIterable {
        case chat
        case calendar
        case projects
        case record
        case more

        var title: String {
            switch self {
            case .chat: return "Chat"
            case .calendar: return "Calendar"
            case .projects: return "Projects"
            case .record: return "Record"
            case .more: return "More"
            }
        }

        var icon: String {
            switch self {
            case .chat: return "house.fill"
            case .calendar: return "calendar"
            case .projects: return "folder.fill"
            case .record: return "mic.circle.fill"
            case .more: return "ellipsis.circle"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label(Tab.chat.title, systemImage: Tab.chat.icon)
                }
                .tag(Tab.chat)

            CalendarView()
                .tabItem {
                    Label(Tab.calendar.title, systemImage: Tab.calendar.icon)
                }
                .tag(Tab.calendar)

            ProjectsView()
                .tabItem {
                    Label(Tab.projects.title, systemImage: Tab.projects.icon)
                }
                .tag(Tab.projects)

            RecordingView { url, title in
                    // Handle recording completion - upload to backend
                    print("Recording completed: \(url), title: \(title ?? "Untitled")")
                }
                .tabItem {
                    Label(Tab.record.title, systemImage: Tab.record.icon)
                }
                .tag(Tab.record)

            MoreView()
                .tabItem {
                    Label(Tab.more.title, systemImage: Tab.more.icon)
                }
                .tag(Tab.more)
        }
        .tint(.blue)
        .overlay(alignment: .top) {
            if !networkMonitor.isConnected {
                NetworkStatusBanner()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationTapped)) { notification in
            handleNotificationNavigation(notification)
        }
    }

    private func handleNotificationNavigation(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let type = userInfo["type"] as? String else {
            return
        }

        switch type {
        case "calendar_reminder":
            selectedTab = .calendar
        case "meeting_summary", "project_update":
            selectedTab = .projects
        case "briefing":
            selectedTab = .more
        case "task_reminder":
            selectedTab = .chat
        default:
            break
        }
    }
}

// MARK: - Network Status Banner

struct NetworkStatusBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
            Text("No Internet Connection")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.orange)
        .cornerRadius(8)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut, value: true)
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(NetworkMonitor.shared)
}

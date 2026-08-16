import Foundation

struct NotificationInbox: Codable, Sendable {
    let notifications: [AppNotification]
    let unreadCount: Int
}

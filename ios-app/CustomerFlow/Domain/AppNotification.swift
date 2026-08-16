import Foundation

struct AppNotification: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let kind: String
    let title: String
    let body: String
    let caseID: UUID?
    let caseReference: String?
    let actorName: String?
    let createdAt: Date
    var readAt: Date?
}

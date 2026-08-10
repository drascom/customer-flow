import Foundation

protocol AppTourStore: Sendable {
    func hasCompleted(userID: String, serverAddress: String, role: UserRole, version: Int) async -> Bool
    func markCompleted(userID: String, serverAddress: String, role: UserRole, version: Int) async
}

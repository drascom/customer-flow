import Foundation

struct AdminAgency: Identifiable, Decodable, Sendable {
    let id: String
    let name: String
    let active: Bool
    let userCount: Int
}

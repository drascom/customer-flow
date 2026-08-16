import Foundation

struct AdminAgency: Identifiable, Decodable, Sendable {
    let id: String
    let name: String
    let active: Bool
    let userCount: Int
    let mcpConfigured: Bool
    let mcpRotatedAt: Date?
}

struct AdminMCPConnection: Decodable, Sendable {
    let agencyID: String
    let agencyName: String
    let endpointURL: String
    let configured: Bool
    let rotatedAt: Date?
    let accessToken: String?
}

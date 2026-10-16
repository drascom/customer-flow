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

struct AdminIntakeForm: Identifiable, Decodable, Sendable {
    let id: String
    let label: String
    let active: Bool
    let agencyID: String
    let agencyName: String
    let doctorID: String?
    let doctorName: String?
    let allowedOrigins: [String]
    let createdAt: Date
    let updatedAt: Date
    let publicKey: String
    let directURL: String
    let iframeCode: String
    let javascriptCode: String
}

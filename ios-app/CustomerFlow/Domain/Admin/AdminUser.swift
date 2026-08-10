import Foundation

struct AdminUser: Identifiable, Decodable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let role: UserRole
    let agencyID: String?
    let agencyName: String?
    let email: String?
    let phone: String?
    var active: Bool
    let createdAt: String
    let caseCount: Int
    let patientCount: Int

    var activitySummary: String {
        switch role {
        case .doctor: "\(patientCount) patients"
        case .agent: "\(caseCount) cases"
        case .admin: "System access"
        case .manager: "Oversight access"
        }
    }
}

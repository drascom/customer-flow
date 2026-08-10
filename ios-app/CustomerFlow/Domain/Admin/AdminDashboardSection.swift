import Foundation

enum AdminDashboardSection: String, CaseIterable, Identifiable {
    case cases = "Cases"
    case users = "Users"

    var id: String { rawValue }
}

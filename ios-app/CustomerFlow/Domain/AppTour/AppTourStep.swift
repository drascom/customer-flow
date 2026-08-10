import Foundation

struct AppTourStep: Identifiable, Sendable {
    let id: Int
    let icon: String
    let title: String
    let message: String
    let tapHint: String
}

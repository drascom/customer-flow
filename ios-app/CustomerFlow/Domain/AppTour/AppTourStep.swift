import Foundation

struct AppTourStep: Identifiable, Sendable {
    let id: Int
    let target: AppTourTarget
    let title: String
    let message: String
}

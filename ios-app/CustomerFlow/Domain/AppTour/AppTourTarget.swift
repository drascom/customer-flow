import Foundation

enum AppTourTarget: Hashable, Sendable {
    case doctorFilter
    case doctorSort
    case doctorCase
    case agentFilter
    case agentNewCase
    case agentCase

    var isOptional: Bool {
        switch self {
        case .doctorCase, .agentCase:
            true
        case .doctorFilter, .doctorSort, .agentFilter, .agentNewCase:
            false
        }
    }
}

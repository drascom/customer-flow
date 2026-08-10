import Foundation

extension UserRole {
    var appTourSteps: [AppTourStep] {
        switch self {
        case .doctor:
            [
                AppTourStep(
                    id: 0,
                    target: .doctorFilter,
                    title: "Choose your queue",
                    message: "Use this filter to see all cases, your waiting cases, unassigned consultations, answered cases or closed cases."
                ),
                AppTourStep(
                    id: 1,
                    target: .doctorSort,
                    title: "Set the order",
                    message: "Switch between the oldest and newest consultations so the right case appears first."
                ),
                AppTourStep(
                    id: 2,
                    target: .doctorCase,
                    title: "Open a consultation",
                    message: "Tap a case to review its photos and conversation. The Doctor Response area is ready at the bottom of the case."
                ),
            ]
        case .agent:
            [
                AppTourStep(
                    id: 0,
                    target: .agentFilter,
                    title: "Filter your cases",
                    message: "Choose all cases, waiting for doctor, waiting for you or closed consultations."
                ),
                AppTourStep(
                    id: 1,
                    target: .agentNewCase,
                    title: "Create a case",
                    message: "Tap New to check the patient and add the note, estimate, price and photos step by step."
                ),
                AppTourStep(
                    id: 2,
                    target: .agentCase,
                    title: "Continue a case",
                    message: "Open an existing case to add an update, review the doctor's answer or confirm and close it when complete."
                ),
            ]
        case .admin, .manager:
            []
        }
    }
}

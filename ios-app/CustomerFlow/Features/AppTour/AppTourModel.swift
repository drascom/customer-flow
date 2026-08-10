import Foundation
import Observation

@MainActor
@Observable
final class AppTourModel {
    private let store: any AppTourStore
    private let version = 1
    private var userID = ""
    private var serverAddress = ""

    var isPresented = false
    var role: UserRole = .doctor
    var steps: [AppTourStep] = []
    var currentStepIndex = 0

    init(store: any AppTourStore) {
        self.store = store
    }

    var currentStep: AppTourStep? {
        steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil
    }

    var isLastStep: Bool {
        !steps.isEmpty && currentStepIndex == steps.count - 1
    }

    func presentIfNeeded(userID: String, serverAddress: String, role: UserRole) async {
        guard role != .admin, !userID.isEmpty, !serverAddress.isEmpty else { return }
        let completed = await store.hasCompleted(
            userID: userID,
            serverAddress: serverAddress,
            role: role,
            version: version
        )
        guard !completed else { return }
        present(userID: userID, serverAddress: serverAddress, role: role)
    }

    func showAgain(userID: String, serverAddress: String, role: UserRole) {
        guard role != .admin else { return }
        present(userID: userID, serverAddress: serverAddress, role: role)
    }

    func goBack() {
        currentStepIndex = max(0, currentStepIndex - 1)
    }

    func goForward() async {
        if isLastStep {
            await finish()
        } else {
            currentStepIndex += 1
        }
    }

    func finish() async {
        await store.markCompleted(
            userID: userID,
            serverAddress: serverAddress,
            role: role,
            version: version
        )
        isPresented = false
    }

    private func present(userID: String, serverAddress: String, role: UserRole) {
        self.userID = userID
        self.serverAddress = serverAddress
        self.role = role
        steps = role.appTourSteps
        currentStepIndex = 0
        isPresented = !steps.isEmpty
    }
}

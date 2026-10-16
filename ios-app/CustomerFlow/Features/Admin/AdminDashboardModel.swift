import Foundation
import Observation

@MainActor
@Observable
final class AdminDashboardModel {
    private let repository: any AdminRepository
    private var reloadRequested = false

    let currentUserID: String
    var users: [AdminUser] = []
    var cases: [AdminCase] = []
    var agencies: [AdminAgency] = []
    var intakeForms: [AdminIntakeForm] = []
    var searchText = ""
    var selectedSection: AdminDashboardSection = .cases
    var caseStatus = ""
    var caseAssignment = ""
    var caseAgency = ""
    var caseDoctorID = ""
    var userRole = ""
    var userStatus = ""
    var userAgencyID = ""
    var isLoading = false
    var errorMessage: String?

    init(repository: any AdminRepository, currentUserID: String) {
        self.repository = repository
        self.currentUserID = currentUserID
    }

    var activeDoctors: [AdminUser] {
        users
            .filter { $0.role == .doctor && $0.active }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var filteredCases: [AdminCase] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return cases.filter { item in
            let searchMatches = query.isEmpty || [
                item.patientName, item.patientID, item.reference, item.agentName,
                item.agencyName ?? "", item.doctorName ?? ""
            ].joined(separator: " ").localizedCaseInsensitiveContains(query)
            let assignmentMatches = caseAssignment.isEmpty
                || (caseAssignment == "assigned" ? item.doctorID != nil : item.doctorID == nil)
            let statusMatches = caseStatus.isEmpty
                || (caseStatus == "completed"
                    ? item.isCompleted
                    : item.status.rawValue == caseStatus && !item.isCompleted)
            return searchMatches
                && statusMatches
                && assignmentMatches
                && (caseAgency.isEmpty || item.agencyName == caseAgency)
                && (caseDoctorID.isEmpty || item.doctorID == caseDoctorID)
        }.sorted { left, right in
            (left.latestMessageAt ?? left.uploadedAt) > (right.latestMessageAt ?? right.uploadedAt)
        }
    }

    var filteredUsers: [AdminUser] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return users.filter { user in
            let searchMatches = query.isEmpty || [
                user.displayName, user.username, user.role.rawValue, user.agencyName ?? ""
            ].joined(separator: " ").localizedCaseInsensitiveContains(query)
            let statusMatches = userStatus.isEmpty
                || (userStatus == "active" ? user.active : !user.active)
            return searchMatches
                && (userRole.isEmpty || user.role.rawValue == userRole)
                && statusMatches
                && (userAgencyID.isEmpty || user.agencyID == userAgencyID)
        }
    }

    var hasActiveFilters: Bool {
        if selectedSection == .cases {
            return !caseStatus.isEmpty || !caseAssignment.isEmpty || !caseAgency.isEmpty || !caseDoctorID.isEmpty
        }
        return !userRole.isEmpty || !userStatus.isEmpty || !userAgencyID.isEmpty
    }

    func load() async {
        guard !isLoading else {
            reloadRequested = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadRequested = false
            do {
                async let usersRequest = repository.fetchUsers()
                async let casesRequest = repository.fetchCases()
                async let agenciesRequest = repository.fetchAgencies()
                async let intakeFormsRequest = repository.fetchIntakeForms()
                (users, cases, agencies, intakeForms) = try await (
                    usersRequest, casesRequest, agenciesRequest, intakeFormsRequest
                )
            } catch {
                guard !Self.isCancellation(error) else { return }
                errorMessage = error.localizedDescription
            }
        } while reloadRequested
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let cocoaError = error as NSError
        return cocoaError.domain == NSURLErrorDomain && cocoaError.code == NSURLErrorCancelled
    }

    func clearFilters() {
        caseStatus = ""
        caseAssignment = ""
        caseAgency = ""
        caseDoctorID = ""
        userRole = ""
        userStatus = ""
        userAgencyID = ""
    }

    func createUser(username: String, displayName: String, role: UserRole, password: String, agencyID: String?) async -> Bool {
        do {
            let user = try await repository.createUser(
                username: username,
                displayName: displayName,
                role: role,
                password: password,
                agencyID: agencyID
            )
            users.append(user)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createAgency(name: String, websiteURL: String?) async -> Bool {
        do {
            agencies.append(try await repository.createAgency(name: name, websiteURL: websiteURL))
            agencies.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            intakeForms = try await repository.fetchIntakeForms()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveAgency(_ agency: AdminAgency, name: String, form: AdminIntakeForm?, allowedOrigins: [String]) async -> Bool {
        do {
            let updated = try await repository.updateAgency(id: agency.id, name: name)
            if let form {
                replaceIntakeForm(try await repository.updateIntakeForm(
                    id: form.id,
                    allowedOrigins: allowedOrigins
                ))
            }
            applyAgencyUpdate(original: agency, updated: updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateAgency(_ agency: AdminAgency, name: String) async -> Bool {
        do {
            let updated = try await repository.updateAgency(id: agency.id, name: name)
            applyAgencyUpdate(original: agency, updated: updated)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setIntakeFormActive(_ form: AdminIntakeForm, active: Bool) async -> AdminIntakeForm? {
        do {
            let updated = try await repository.setIntakeFormActive(id: form.id, active: active)
            replaceIntakeForm(updated)
            return updated
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteAgency(_ agency: AdminAgency) async -> String? {
        do {
            let mode = try await repository.deleteAgency(id: agency.id)
            agencies = try await repository.fetchAgencies()
            intakeForms = try await repository.fetchIntakeForms()
            return mode
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportIntegrationGuide(for agency: AdminAgency, accessToken: String?) async -> Data? {
        do {
            return try await repository.exportAgencyIntegrationGuide(
                agencyID: agency.id,
                accessToken: accessToken
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func transferPatientAgency(_ item: AdminCase, agencyID: String, reason: String) async -> Bool {
        do {
            try await repository.transferPatientAgency(
                patientID: item.patientID,
                agencyID: agencyID,
                reason: reason
            )
            cases = try await repository.fetchCases()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func replaceIntakeForm(_ updated: AdminIntakeForm) {
        if let index = intakeForms.firstIndex(where: { $0.id == updated.id }) {
            intakeForms[index] = updated
        } else {
            intakeForms.append(updated)
        }
    }

    private func applyAgencyUpdate(original: AdminAgency, updated: AdminAgency) {
        guard let index = agencies.firstIndex(where: { $0.id == original.id }) else { return }
        agencies[index] = updated
        agencies.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for caseIndex in cases.indices where cases[caseIndex].agencyName == original.name {
            cases[caseIndex].agencyName = updated.name
        }
        for userIndex in users.indices where users[userIndex].agencyID == original.id {
            users[userIndex] = AdminUser(
                id: users[userIndex].id,
                username: users[userIndex].username,
                displayName: users[userIndex].displayName,
                role: users[userIndex].role,
                agencyID: users[userIndex].agencyID,
                agencyName: updated.name,
                email: users[userIndex].email,
                phone: users[userIndex].phone,
                active: users[userIndex].active,
                createdAt: users[userIndex].createdAt,
                caseCount: users[userIndex].caseCount,
                patientCount: users[userIndex].patientCount
            )
        }
    }

    func fetchMCPConnection(for agency: AdminAgency) async -> AdminMCPConnection? {
        do {
            return try await repository.fetchMCPConnection(agencyID: agency.id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func rotateMCPToken(for agency: AdminAgency) async -> AdminMCPConnection? {
        do {
            let connection = try await repository.rotateMCPToken(agencyID: agency.id)
            if let index = agencies.firstIndex(where: { $0.id == agency.id }) {
                agencies[index] = AdminAgency(
                    id: agencies[index].id,
                    name: agencies[index].name,
                    active: agencies[index].active,
                    userCount: agencies[index].userCount,
                    mcpConfigured: true,
                    mcpRotatedAt: connection.rotatedAt
                )
            }
            return connection
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateUser(
        _ user: AdminUser,
        username: String,
        displayName: String,
        role: UserRole,
        password: String?,
        agencyID: String?
    ) async -> Bool {
        do {
            let updated = try await repository.updateUser(
                id: user.id,
                username: username,
                displayName: displayName,
                role: role,
                password: password,
                agencyID: agencyID
            )
            guard let index = users.firstIndex(where: { $0.id == user.id }) else { return true }
            users[index] = updated
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setUserActive(_ user: AdminUser, active: Bool) async {
        do {
            try await repository.setUserActive(id: user.id, active: active)
            guard let index = users.firstIndex(where: { $0.id == user.id }) else { return }
            users[index].active = active
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteUser(_ user: AdminUser) async {
        do {
            try await repository.deleteUser(id: user.id)
            users.removeAll { $0.id == user.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func assignDoctor(to item: AdminCase, doctorID: String?, reason: String) async {
        do {
            try await repository.assignDoctor(patientID: item.patientID, doctorID: doctorID, reason: reason)
            let doctorName = users.first(where: { $0.id == doctorID })?.displayName
            for index in cases.indices where cases[index].patientID == item.patientID && cases[index].status != .closed {
                cases[index].doctorID = doctorID
                cases[index].doctorName = doctorName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unconfirmCase(_ item: AdminCase) async {
        do {
            try await repository.unconfirmCase(caseID: item.id)
            cases = try await repository.fetchCases()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeCase(_ item: AdminCase) async -> Bool {
        do {
            try await repository.completeCase(caseID: item.id)
            cases = try await repository.fetchCases()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteCase(_ item: AdminCase) async {
        do {
            try await repository.deleteCase(caseID: item.id)
            cases.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purgePhoto(id: String) async {
        do {
            try await repository.purgePhoto(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addOperationalNote(to item: AdminCase, text: String) async -> AdminCase? {
        do {
            try await repository.addOperationalNote(caseID: item.id, text: text)
            let refreshedCases = try await repository.fetchCases()
            cases = refreshedCases
            return refreshedCases.first { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

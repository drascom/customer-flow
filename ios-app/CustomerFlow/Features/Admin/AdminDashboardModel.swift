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
            return searchMatches
                && (caseStatus.isEmpty || item.status.rawValue == caseStatus)
                && assignmentMatches
                && (caseAgency.isEmpty || item.agencyName == caseAgency)
                && (caseDoctorID.isEmpty || item.doctorID == caseDoctorID)
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
                (users, cases, agencies) = try await (usersRequest, casesRequest, agenciesRequest)
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

    func createAgency(name: String) async -> Bool {
        do {
            agencies.append(try await repository.createAgency(name: name))
            agencies.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateAgency(_ agency: AdminAgency, name: String) async -> Bool {
        do {
            let updated = try await repository.updateAgency(id: agency.id, name: name)
            guard let index = agencies.firstIndex(where: { $0.id == agency.id }) else { return true }
            agencies[index] = updated
            agencies.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for caseIndex in cases.indices where cases[caseIndex].agencyName == agency.name {
                cases[caseIndex].agencyName = updated.name
            }
            for userIndex in users.indices where users[userIndex].agencyID == agency.id {
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
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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

    func purgePhoto(id: String) async {
        do {
            try await repository.purgePhoto(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
